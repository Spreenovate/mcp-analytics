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

	// Step 3: Reverse-DNS for Anthropic. Only fires when the UA gives
	// some hint that it might actually be Anthropic — looking for
	// "anthropic" or "claude" substring. Without this gate, every
	// unmatched-IP request would do two synchronous DNS lookups
	// (LookupAddr + LookupIPAddr forward-confirm), which an attacker
	// could weaponize as a DoS amplifier by flooding random
	// browser-UA + random-IP requests. The gate keeps the FCrDNS
	// path available for "Anthropic deploys a new UA we haven't
	// curated yet" cases without exposing it to all unknown traffic.
	//
	// Trade-off: if Anthropic ever ships a crawler whose UA contains
	// neither "anthropic" nor "claude", we miss it until the UA
	// pattern list is updated. Acceptable.
	if ip != nil && c.dnsLookupFn != nil && uaSuggestsAnthropic(userAgent) {
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
// classification can be considered consistent.
//
//   - Same exact class → agree.
//   - Both AI-related (ai_*) → agree (UA might say "GPTBot" while
//     IP hits the broader "openai-gptbot" range; the granularity
//     differs but both point at OpenAI's training crawler).
//   - UA matched a class with NO authoritative IP ranges
//     (social_unfurl, scanner, bot_other) and IP is in cloud-infra
//     → agree. Slackbot, facebookexternalhit, LinkedInBot etc.
//     legitimately run on AWS/GCP/Cloudflare; we have no published
//     range for them, so cloud-infra match doesn't contradict the UA.
//
// Conservative on the disagreement side: when UA matched a class
// that DOES have authoritative ranges (ai_*, search_index) and the
// IP is somewhere else (other vendor or cloud-infra-only), that's
// a spoof signal — caller demotes to bot_other.
func classesAgree(uaClass, ipClass Class) bool {
	if uaClass == ipClass {
		return true
	}
	if strings.HasPrefix(uaClass, "ai_") && strings.HasPrefix(ipClass, "ai_") {
		return true
	}
	if isCloudInfraClass(ipClass) && !hasAuthoritativeIPRanges(uaClass) {
		return true
	}
	return false
}

// hasAuthoritativeIPRanges reports whether we have published IP-range
// data for the given class. If we DO and the IP isn't in those ranges,
// the UA-vs-IP mismatch is meaningful (spoof). If we DON'T, the IP
// signal is non-authoritative for that class (e.g. Slackbot can run
// from anywhere on AWS).
//
// Drift risk: if we ever add a vendor JSON for social_unfurl (e.g.
// Slack publishes IP ranges), update this function. The Source list
// in source.go is the source of truth — this function mirrors which
// classes are represented there.
func hasAuthoritativeIPRanges(c Class) bool {
	switch c {
	case ClassAIUserAction, ClassAISearch, ClassAITraining, ClassSearchIndex:
		return true
	default:
		return false
	}
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

// uaSuggestsAnthropic returns true if the UA contains a substring that
// hints this might be Anthropic traffic (where reverse-DNS verification
// is worth doing because Anthropic doesn't publish IP ranges). Used as
// a gate around the FCrDNS lookup in Classify step 3 so we don't fire
// DNS for arbitrary unrecognized traffic — that would be a DoS
// amplifier, since DNS is synchronous and 500ms per miss.
func uaSuggestsAnthropic(ua string) bool {
	if ua == "" {
		return false
	}
	lo := strings.ToLower(ua)
	return strings.Contains(lo, "anthropic") || strings.Contains(lo, "claude")
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
