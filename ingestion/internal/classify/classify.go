package classify

import (
	"net"
	"strings"
)

// Classifier is the assembled object the ingest server calls into. It
// composes UA-pattern matching, IP-trie lookup, reverse-DNS, and a
// generic-Chrome-from-cloud heuristic into a single Classify(ua, ip)
// call.
//
// Build via NewClassifier; bootstrap the IP-trie via classify.Bootstrap.
type Classifier struct {
	ip  *AtomicLookup
	dns *dnsCache

	// Hooks are exposed for tests. Production wiring uses the live
	// dnsCache and AtomicLookup.
	dnsLookupFn func(ip net.IP) (Class, string, bool)
	ipLookupFn  func(ip net.IP) (Class, string, bool)
	ipIsCloudFn func(ip net.IP) bool
}

// NewClassifier wires up the production dependencies. The returned
// classifier is safe for concurrent use; callers should keep one
// instance for the process lifetime and read it from the hot path.
func NewClassifier(ip *AtomicLookup) *Classifier {
	dc := newDNSCache()
	c := &Classifier{
		ip:  ip,
		dns: dc,
	}
	c.dnsLookupFn = dc.Lookup
	c.ipLookupFn = ip.Lookup
	c.ipIsCloudFn = ip.IsCloud
	return c
}

// Classify returns the traffic_class for an incoming request.
//
// Decision tree:
//
//  1. UA matches a specific marker (GPTBot, Googlebot, Slackbot, ...)
//     → use that. If we also have an IP and it falls inside the
//     matching vendor's range, the trust score is highest. If the IP
//     contradicts (UA says GPTBot, IP is some random VPS), demote to
//     bot_other — i.e. spoofed UA.
//
//  2. UA didn't match a specific marker (or matched only a generic
//     bot_other) → consult the IP trie. If the IP is in a known
//     vendor range (e.g. an OpenAI range with no UA), use the trie's
//     class. This catches header-stripping proxies and the rare
//     vendor that lies about UA.
//
//  3. Reverse-DNS for *.anthropic.com (FCrDNS-verified) gets us the
//     ai_training / ai_user_action distinction Anthropic doesn't
//     publish ranges for. Only fired if both UA and IP-trie miss, to
//     keep the hot-path fast.
//
//  4. Heuristic: UA looks like a plain browser (Chrome/Firefox/Safari
//     with no bot marker) BUT the IP is from a known cloud-infra
//     range (AWS/GCP/Azure/CF) → scanner. This catches "I copied my
//     User-Agent from the dev console and ran headless Chrome from
//     EC2".
//
//  5. Default → user.
//
// Trust order: UA-marker > IP-vendor > reverse-DNS > heuristic.
//
// IP may be nil (e.g. malformed X-Forwarded-For); the function still
// returns a valid Class (usually ClassUser unless UA already says bot).
func (c *Classifier) Classify(userAgent string, ip net.IP) Class {
	uaClass := classifyUA(userAgent)

	// Step 1: UA matched a specific (non-tail) class.
	if uaClass != "" && !isTailClass(uaClass) {
		// If we have an IP and it falls in a vendor range, validate
		// the UA matches what that vendor publishes.
		if ip != nil {
			if ipClass, _, ok := c.ipLookup(ip); ok {
				// Both signals agree: trust it (use UA's class which
				// is more specific within the same vendor — e.g. UA
				// distinguishes GPTBot from ChatGPT-User even though
				// both might share IP space).
				if classesAgree(uaClass, ipClass) {
					return uaClass
				}
				// UA and IP disagree → spoof signal. Two flavours,
				// both demoted to bot_other:
				//
				//   - UA="GPTBot" + IP in AWS-only range (no
				//     specific OpenAI nested) → fake bot from random
				//     EC2 box.
				//   - UA="Googlebot" + IP in actual OpenAI range →
				//     header-stuffing attempt, can't trust either
				//     signal individually.
				//
				// Returning bot_other rather than the IP's class
				// avoids inflating per-vendor counters with traffic
				// that's deliberately misrepresenting itself.
				return ClassBotOther
			}
			// IP not in any vendor or cloud-infra range (residential
			// IP). Could be a small AI startup whose ranges we
			// haven't curated yet, or a person running a self-hosted
			// crawler. Trust the UA — least-bad option.
			return uaClass
		}
		// No IP info — trust the UA.
		return uaClass
	}

	// Step 2: IP-trie says something about this IP.
	if ip != nil {
		if ipClass, _, ok := c.ipLookup(ip); ok {
			// Pure IP match (UA was empty or generic). Use the IP's
			// class — except if it's a cloud-infra match (AWS/GCP/CF):
			// we don't classify generic-cloud traffic as scanner just
			// for being on cloud infra without a UA hint.
			if !isCloudInfraClass(ipClass) {
				return ipClass
			}
		}
	}

	// Step 3: Reverse-DNS for Anthropic. Only if neither UA nor IP-trie
	// pinned the class. Only fires for IPs that aren't in any vendor
	// range AND don't have a recognizable UA.
	if ip != nil && c.dnsLookupFn != nil {
		if dnsClass, _, ok := c.dnsLookupFn(ip); ok {
			return dnsClass
		}
	}

	// Step 4: Generic-browser-UA + cloud-IP heuristic → scanner.
	if ip != nil && looksLikeGenericBrowser(userAgent) && c.isCloud(ip) {
		return ClassScanner
	}

	// Step 5: UA matched a tail (generic) class earlier? Use it.
	if uaClass != "" {
		return uaClass
	}

	// Default: real user.
	return ClassUser
}

// --- helpers ---------------------------------------------------------

func (c *Classifier) ipLookup(ip net.IP) (Class, string, bool) {
	if c.ipLookupFn == nil {
		return "", "", false
	}
	return c.ipLookupFn(ip)
}

func (c *Classifier) isCloud(ip net.IP) bool {
	if c.ipIsCloudFn == nil {
		return false
	}
	return c.ipIsCloudFn(ip)
}

// isTailClass reports whether a Class is one of the broad
// "we know it's a bot, just don't know what kind" buckets. Tail
// classes shouldn't trigger the IP-spoof-check above because they're
// already the catch-all bucket.
func isTailClass(c Class) bool {
	return c == ClassBotOther || c == ""
}

// classesAgree reports whether a UA classification and an IP-trie
// classification can be considered consistent. Defined narrowly:
//
//   - Same exact class → agree.
//   - Both AI-related (ai_*) → agree (UA might say "GPTBot" while IP
//     hits the broader "openai-gptbot" range; the granularity differs
//     but both point at OpenAI's training crawler).
//   - Both search-index → agree.
//
// This is conservative — when in doubt we treat them as disagreeing,
// which routes the request through the IP-trie's class rather than
// the UA's. That's safer because IP ranges are harder to spoof.
func classesAgree(uaClass, ipClass Class) bool {
	if uaClass == ipClass {
		return true
	}
	uAI := strings.HasPrefix(uaClass, "ai_")
	iAI := strings.HasPrefix(ipClass, "ai_")
	if uAI && iAI {
		return true
	}
	if uaClass == ClassSearchIndex && ipClass == ClassSearchIndex {
		return true
	}
	return false
}

// isCloudInfraClass reports whether a Class came from a cloud-infra
// range (AWS/GCP/Azure/CF). These are tagged ClassScanner in the
// source list but we don't actually classify cloud-IP traffic as
// scanner unless additional signals agree (see Classify step 4).
func isCloudInfraClass(c Class) bool {
	// Currently all cloud-infra sources map to ClassScanner. If we
	// ever add cloud sources mapping to other classes, expand this.
	// (We could check the trie's IsCloudInfra flag directly, but the
	// IPLookup interface currently returns only Class+Provider; this
	// keeps the hot-path interface narrow.)
	return c == ClassScanner
}

// looksLikeGenericBrowser returns true for UAs that look like a vanilla
// Chrome/Firefox/Safari with no bot marker. Used by the heuristic
// layer to flag "this is suspiciously generic, plus cloud IP".
//
// Implementation: a UA "looks like a browser" if it contains one of
// the major browser tokens AND classifyUA didn't already match a bot
// pattern. We rely on the caller having already checked classifyUA.
func looksLikeGenericBrowser(ua string) bool {
	if ua == "" {
		return false
	}
	lo := strings.ToLower(ua)
	browserMarkers := []string{
		"chrome/", "firefox/", "safari/", "edge/", "edg/",
		"mozilla/5.0", "applewebkit/",
	}
	for _, m := range browserMarkers {
		if strings.Contains(lo, m) {
			return true
		}
	}
	return false
}
