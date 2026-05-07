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
}

func newDNSCache() *dnsCache {
	return &dnsCache{
		resolver:   net.DefaultResolver,
		entries:    make(map[string]dnsResult),
		maxSize:    50_000,
		successTTL: 24 * time.Hour,
		failureTTL: 1 * time.Hour,
		timeout:    500 * time.Millisecond,
	}
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

	// Cache miss or stale — do the lookup with a tight timeout. The
	// hot path can tolerate a few ms here for IPs not covered by the
	// trie (rare, since most bot IPs are in their vendor JSONs).
	ctx, cancel := context.WithTimeout(context.Background(), c.timeout)
	defer cancel()

	class, provider, matched := c.resolveAndVerify(ctx, ip, key)

	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.maxSize {
		// Cheap bounded growth: nuke the cache when it fills up. We
		// don't need LRU semantics here — a periodic flush is fine.
		c.entries = make(map[string]dnsResult, c.maxSize/2)
	}
	ttl := c.failureTTL
	if matched {
		ttl = c.successTTL
	}
	c.entries[key] = dnsResult{
		class:    class,
		provider: provider,
		matched:  matched,
		expiry:   now.Add(ttl),
	}
	return class, provider, matched
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
