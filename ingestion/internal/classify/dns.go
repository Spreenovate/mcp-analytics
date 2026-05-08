package classify

import (
	"context"
	"net"
	"strings"
	"sync"
	"time"
)

// reverseDNS is a small in-memory cache around net.DefaultResolver's
// LookupAddr, used as the Anthropic fallback (Anthropic doesn't
// publish IP ranges; we verify by reverse-DNS to *.anthropic.com and
// then forward-confirm via LookupHost on the returned name).
//
// Cache TTL is 24h on success, 1h on failure (avoid hammering DNS for
// every spoofed-UA request from random scanners). The cache is bounded
// to ~50k entries via FIFO eviction on insert; the hot path is best-
// effort and never blocks.
//
// Threat model note: reverse-DNS is spoofable by the IP owner. The
// FCrDNS pattern (reverse → forward → matches original IP) is the
// industry standard mitigation and what Google documents for their
// own crawler verification. We adopt the same pattern here.

type dnsResult struct {
	class    Class
	provider string
	matched  bool
	expiry   time.Time
}

type dnsCache struct {
	resolver *net.Resolver
	mu       sync.Mutex
	entries  map[string]dnsResult
	maxSize  int

	// successTTL/failureTTL configurable so tests can shrink them.
	successTTL time.Duration
	failureTTL time.Duration
	timeout    time.Duration

	// Per-process rate-limit backstop. Even if the cache gets nuked
	// or a hostile UA cycles through unique IPs faster than the cache
	// can absorb, this caps DNS-call concurrency at a level the host
	// resolver can sustain. Token bucket: refills at refillRate per
	// second, max burst of bucketSize. When empty, Lookup returns
	// (false) without issuing a DNS query — caller falls through to
	// classifyUA / heuristic / ClassUser default.
	rlMu       sync.Mutex
	rlTokens   float64
	rlLastFill time.Time
	rlRate     float64 // tokens/sec
	rlMax      float64 // max burst
}

func newDNSCache() *dnsCache {
	now := time.Now()
	return &dnsCache{
		resolver:   net.DefaultResolver,
		entries:    make(map[string]dnsResult),
		maxSize:    50_000,
		successTTL: 24 * time.Hour,
		failureTTL: 1 * time.Hour,
		timeout:    500 * time.Millisecond,
		rlTokens:   100,
		rlMax:      100,
		rlRate:     50, // 50 lookups/sec sustained, 100 burst
		rlLastFill: now,
	}
}

// allowLookup returns true if the rate-limit budget allows another
// real DNS lookup. Uses a simple token-bucket (no external dep) since
// we only need a coarse backstop, not precision.
func (c *dnsCache) allowLookup(now time.Time) bool {
	c.rlMu.Lock()
	defer c.rlMu.Unlock()
	elapsed := now.Sub(c.rlLastFill).Seconds()
	if elapsed > 0 {
		c.rlTokens += elapsed * c.rlRate
		if c.rlTokens > c.rlMax {
			c.rlTokens = c.rlMax
		}
		c.rlLastFill = now
	}
	if c.rlTokens >= 1 {
		c.rlTokens--
		return true
	}
	return false
}

// Lookup returns the class implied by reverse-DNS, or ("", "", false)
// if the IP doesn't FCrDNS-verify against a known suffix.
//
// Currently only Anthropic is queried this way — for everything else
// we have authoritative IP ranges and don't need DNS.
func (c *dnsCache) Lookup(ip net.IP) (Class, string, bool) {
	if ip == nil {
		return "", "", false
	}

	key := ip.String()
	now := time.Now()

	c.mu.Lock()
	if r, ok := c.entries[key]; ok && now.Before(r.expiry) {
		c.mu.Unlock()
		return r.class, r.provider, r.matched
	}
	c.mu.Unlock()

	// Cache miss or stale. Two safety brakes before issuing real DNS:
	//
	//   1. Rate-limit backstop. Even if the cache gets nuked or an
	//      attacker cycles through unique IPs faster than the cache
	//      can absorb, this caps the resolver pressure. When the
	//      bucket is empty, return unmatched and let the caller fall
	//      back to classifyUA / heuristic / default.
	//
	//   2. Per-IP timeout (500ms by default). Hot path can tolerate
	//      a few ms; the gate above (uaSuggestsAnthropic) ensures
	//      this only fires for plausibly-Anthropic UAs.
	if !c.allowLookup(now) {
		// Cache the negative result with the failure TTL so we don't
		// hammer the bucket on every retry — short TTL so a transient
		// burst doesn't blackhole legitimate Anthropic IPs forever.
		c.recordResult(key, "", "", false, c.failureTTL)
		return "", "", false
	}

	ctx, cancel := context.WithTimeout(context.Background(), c.timeout)
	defer cancel()

	class, provider, matched := c.resolveAndVerify(ctx, ip, key)

	ttl := c.failureTTL
	if matched {
		ttl = c.successTTL
	}
	c.recordResult(key, class, provider, matched, ttl)
	return class, provider, matched
}

// recordResult writes a dnsResult to the cache, bounded growth via
// proportional drop (eject ~25% of entries when full, not 100%, so a
// post-nuke burst doesn't re-trigger 50k DNS lookups in one second).
func (c *dnsCache) recordResult(key string, class Class, provider string, matched bool, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.maxSize {
		// Drop ~25% of entries (random by map-iteration order). Not
		// LRU — but we don't need LRU strictness, we just need to
		// avoid the "all 50k miss simultaneously" failure mode.
		dropTarget := c.maxSize / 4
		dropped := 0
		for k := range c.entries {
			if dropped >= dropTarget {
				break
			}
			delete(c.entries, k)
			dropped++
		}
	}
	c.entries[key] = dnsResult{
		class:    class,
		provider: provider,
		matched:  matched,
		expiry:   time.Now().Add(ttl),
	}
}

// resolveAndVerify performs FCrDNS verification:
//
//   1. Reverse-DNS the IP → list of names
//   2. If any name has a recognized suffix (e.g. *.anthropic.com),
//      forward-resolve that name back to a list of IPs
//   3. If the original IP appears in step 2's results, we trust the
//      classification. Otherwise reject (could be a spoofed PTR).
func (c *dnsCache) resolveAndVerify(ctx context.Context, ip net.IP, ipStr string) (Class, string, bool) {
	names, err := c.resolver.LookupAddr(ctx, ipStr)
	if err != nil || len(names) == 0 {
		return "", "", false
	}

	for _, name := range names {
		name = strings.TrimSuffix(strings.ToLower(name), ".")

		var class Class
		var provider string
		switch {
		case strings.HasSuffix(name, ".anthropic.com"):
			// Anthropic publishes no IP-range JSON, but documents that
			// their crawlers reverse-DNS into *.anthropic.com.
			// Distinguish ClaudeBot (training) from Claude-User
			// (live-browse) via the hostname — Anthropic uses
			// claudebot-*.anthropic.com vs anthropic-ai-*.anthropic.com.
			// Be conservative: if subdomain ambiguous, default to
			// ai_training (the more cautious classification — under-
			// counts AI-mediated humans rather than over-counting).
			class = ClassAITraining
			provider = "anthropic"
			if strings.Contains(name, "user") || strings.Contains(name, "claude-user") {
				class = ClassAIUserAction
			}
		default:
			continue
		}

		// FCrDNS forward-confirmation. Without this step a malicious
		// IP owner could set a PTR to claim *.anthropic.com and we'd
		// trust it.
		addrs, err := c.resolver.LookupIPAddr(ctx, name)
		if err != nil || len(addrs) == 0 {
			continue
		}
		for _, a := range addrs {
			if a.IP.Equal(ip) {
				return class, provider, true
			}
		}
		// Name claimed an Anthropic suffix but didn't forward-confirm
		// — record as not-matched (treat as bot_other or fall through
		// to UA classification).
	}
	return "", "", false
}
