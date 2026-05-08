package classify

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// --- CIDR prefix-floor (defense against vendor-compromise pushing 0/0) ---

func TestParseCIDR_RejectsOverlyBroadIPv4(t *testing.T) {
	tooBroad := []string{
		"0.0.0.0/0",
		"10.0.0.0/4",
		"192.0.0.0/7",
	}
	for _, raw := range tooBroad {
		if _, err := parseCIDR(raw); err == nil {
			t.Errorf("expected rejection for too-broad IPv4 %q", raw)
		}
	}
}

func TestParseCIDR_RejectsOverlyBroadIPv6(t *testing.T) {
	tooBroad := []string{
		"::/0",
		"2001::/16",
		"2603::/24",
	}
	for _, raw := range tooBroad {
		if _, err := parseCIDR(raw); err == nil {
			t.Errorf("expected rejection for too-broad IPv6 %q", raw)
		}
	}
}

func TestParseCIDR_AcceptsLegitimatePrefixes(t *testing.T) {
	ok := []string{
		"3.0.0.0/8",         // AWS broadest
		"66.249.64.0/19",    // Google googlebot
		"23.98.142.176/28",  // OpenAI typical
		"2603:1030:7::/48",  // OpenAI IPv6
		"2400:6500::/40",    // AWS IPv6 broad
	}
	for _, raw := range ok {
		if _, err := parseCIDR(raw); err != nil {
			t.Errorf("legitimate prefix %q rejected: %v", raw, err)
		}
	}
}

func TestParseCIDR_RejectsBareIPsAtBoundary(t *testing.T) {
	// Bare IP becomes /32 v4 or /128 v6 — both above the floor, so
	// these should always succeed.
	for _, raw := range []string{"1.2.3.4", "2001:db8::1"} {
		if _, err := parseCIDR(raw); err != nil {
			t.Errorf("bare IP %q should parse as host route: %v", raw, err)
		}
	}
}

// --- Vendor-compromise scenario: 0/0 in a JSON payload is rejected ----

func TestParseOpenAI_RejectsHostileWildcard(t *testing.T) {
	body := `{"prefixes":[
		{"ipv4Prefix":"0.0.0.0/0"},
		{"ipv4Prefix":"23.98.142.176/28"}
	]}`
	nets, err := ParseSource("openai", strings.NewReader(body))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(nets) != 1 {
		t.Errorf("expected 1 valid CIDR (the wildcard rejected, the legit one accepted), got %d", len(nets))
	}
	if len(nets) == 1 && nets[0].String() != "23.98.142.176/28" {
		t.Errorf("kept wrong entry: %s", nets[0].String())
	}
}

// --- v4-mapped IPv6 bypass (HIGH from Round 2 review) ---------------

func TestParseCIDR_RejectsV4MappedWildcard(t *testing.T) {
	// Hostile vendor entry that defeats the IPv4 floor by hiding behind
	// an IPv6 wrapper. cidranger matches IPv4 lookups against this, so
	// failing to reject it would hijack the entire IPv4 space.
	hostile := []string{
		"::ffff:0.0.0.0/96",   // entire IPv4 space
		"::ffff:0.0.0.0/100",  // /4 IPv4 equivalent — still under /8 floor
		"::ffff:128.0.0.0/103", // /7 IPv4 equivalent
	}
	for _, raw := range hostile {
		if _, err := parseCIDR(raw); err == nil {
			t.Errorf("expected rejection for v4-mapped wildcard %q", raw)
		}
	}
}

func TestParseCIDR_AcceptsLegitV4Mapped(t *testing.T) {
	// Real v4-mapped prefixes that are above the IPv4 floor (effective
	// >= /8) should still be accepted — we don't want to break a
	// vendor that publishes ranges in v4-mapped notation.
	ok := []string{
		"::ffff:3.0.0.0/104",  // effective /8 — at the floor
		"::ffff:23.98.142.176/124", // effective /28
	}
	for _, raw := range ok {
		if _, err := parseCIDR(raw); err != nil {
			t.Errorf("legitimate v4-mapped prefix %q rejected: %v", raw, err)
		}
	}
}

// --- Drift prevention: hasAuthoritativeIPRanges vs Sources() ---------

func TestHasAuthoritativeIPRanges_CoversEveryNonCloudSource(t *testing.T) {
	// Anyone who adds a Source in source.go must end up with
	// hasAuthoritativeIPRanges returning true for that source's Class
	// (unless it's marked IsCloudInfra). Since we now derive the set
	// from Sources() this should always pass — but the test pins the
	// invariant so a refactor that breaks the linkage fails loudly.
	for _, src := range Sources() {
		if src.IsCloudInfra {
			continue
		}
		if !hasAuthoritativeIPRanges(src.Class) {
			t.Errorf("source %q is non-cloud-infra with class %q but "+
				"hasAuthoritativeIPRanges returns false — derivation broken",
				src.Name, src.Class)
		}
	}
}

// --- Slackbot-from-AWS: Classify() level integration ----------------

func TestClassifier_SlackbotFromAWS_StaysSocialUnfurl(t *testing.T) {
	// Round 1 fixed classesAgree at the helper level; this test pins
	// the full Classify() decision tree end-to-end. Slackbot
	// legitimately runs on AWS — must NOT demote to bot_other just
	// because the IP is in a cloud-infra range.
	_, awsNet, _ := net.ParseCIDR("3.0.0.0/8")
	lookup := &AtomicLookup{}
	lookup.Store(NewTrie([]TrieEntry{
		{Net: awsNet, Class: ClassScanner, Provider: "aws", IsCloudInfra: true},
	}))
	c := NewClassifier(lookup)
	got := c.Classify(
		"Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
		net.ParseIP("3.42.99.99"))
	if got != ClassSocialUnfurl {
		t.Errorf("Slackbot from AWS IP: got %q want %q (must stay social_unfurl despite cloud-infra IP — social_unfurl has no authoritative ranges)",
			got, ClassSocialUnfurl)
	}
}

// --- DNS gating (no longer fires for unrelated UAs) -----------------

func TestClassifier_DNSGatedByUA(t *testing.T) {
	// Prove: a UA with no anthropic/claude hint never causes a DNS
	// lookup, even when the IP is unknown to the trie.
	dnsCalls := 0
	c := NewClassifier(&AtomicLookup{})
	c.dnsLookupFn = func(_ net.IP) (Class, string, bool) {
		dnsCalls++
		return ClassAITraining, "anthropic", true
	}
	// IP is unknown, UA looks like a human Chrome.
	got := c.Classify(
		"Mozilla/5.0 (Macintosh) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		net.ParseIP("198.51.100.42"))
	if got != ClassUser {
		t.Errorf("got %q want %q", got, ClassUser)
	}
	if dnsCalls != 0 {
		t.Errorf("DNS fired %d times for non-anthropic UA — should be 0", dnsCalls)
	}
}

func TestClassifier_DNSFiresWhenUAHintsAnthropic(t *testing.T) {
	dnsCalls := 0
	c := NewClassifier(&AtomicLookup{})
	c.dnsLookupFn = func(_ net.IP) (Class, string, bool) {
		dnsCalls++
		return ClassAITraining, "anthropic", true
	}
	// UA mentions anthropic but doesn't match a curated marker.
	got := c.Classify(
		"Mozilla/5.0 (custom-anthropic-experimental/1.0)",
		net.ParseIP("198.51.100.42"))
	if dnsCalls != 1 {
		t.Errorf("expected 1 DNS call for anthropic-hint UA, got %d", dnsCalls)
	}
	if got != ClassAITraining {
		t.Errorf("got %q want %q", got, ClassAITraining)
	}
}

// --- classesAgree edge cases (Slackbot-from-AWS bug fix) -------------

func TestClassesAgree_SlackbotFromCloud(t *testing.T) {
	// social_unfurl has no published IP ranges → cloud-infra IP
	// shouldn't trigger spoof demotion.
	if !classesAgree(ClassSocialUnfurl, ClassScanner) {
		t.Error("Slackbot UA + AWS IP (cloud-infra) must AGREE — social_unfurl has no ranges")
	}
}

func TestClassesAgree_GptbotFromCloud_StillSpoof(t *testing.T) {
	// ai_training HAS published IP ranges — cloud-infra IP without
	// vendor match means spoof.
	if classesAgree(ClassAITraining, ClassScanner) {
		t.Error("GPTBot UA + AWS IP must DISAGREE — ai_training has authoritative ranges")
	}
}

func TestClassesAgree_GooglebotFromCloud_StillSpoof(t *testing.T) {
	if classesAgree(ClassSearchIndex, ClassScanner) {
		t.Error("Googlebot UA + AWS IP must DISAGREE — search_index has authoritative ranges")
	}
}

func TestClassesAgree_GooglebotFromOpenAIRange_Spoof(t *testing.T) {
	// Both have ranges, but for different vendors → spoof.
	if classesAgree(ClassSearchIndex, ClassAITraining) {
		t.Error("Googlebot UA + OpenAI-range IP must DISAGREE")
	}
}

// --- Refresher: prevSwapTotal is cached, not read from gauges --------

func TestRefresher_PrevTotalCachedAcrossRefreshes(t *testing.T) {
	// Two successful refreshes; the second produces fewer entries
	// and would be rejected if we compare against the cached prev.
	count := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		count++
		var prefixes []map[string]string
		n := 30
		if count == 1 {
			n = 100
		}
		for i := 0; i < n; i++ {
			prefixes = append(prefixes, map[string]string{
				"ipv4Prefix": fmt.Sprintf("10.%d.0.0/24", i), // 0-255 unique
			})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"prefixes": prefixes})
	}))
	defer srv.Close()

	mx := NewMetrics()
	target := &AtomicLookup{}
	r := NewRefresher(target, mx, RefreshConfig{
		MinShrinkRatio: 0.5,
		SourceFn: func() []Source {
			return []Source{{Name: "fake", URL: srv.URL, Format: "openai", Class: ClassAITraining}}
		},
	})

	if err := r.RunOnce(context.Background()); err != nil {
		t.Fatalf("first: %v", err)
	}
	if r.prevSwapTotal != 100 {
		t.Errorf("prevSwapTotal after first: got %d want 100", r.prevSwapTotal)
	}

	// Second should reject (30/100 = 0.30 < 0.50).
	err := r.RunOnce(context.Background())
	if err == nil {
		t.Fatal("expected rejection")
	}
	if r.prevSwapTotal != 100 {
		t.Errorf("prevSwapTotal after rejected: got %d want 100 (unchanged)", r.prevSwapTotal)
	}
}

func TestRefresher_PartialSuccessRecorded(t *testing.T) {
	okSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"prefixes": []map[string]string{{"ipv4Prefix": "23.98.142.176/28"}},
		})
	}))
	defer okSrv.Close()
	failSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(500)
	}))
	defer failSrv.Close()

	mx := NewMetrics()
	target := &AtomicLookup{}
	r := NewRefresher(target, mx, RefreshConfig{
		HTTPTimeout: 2 * time.Second,
		SourceFn: func() []Source {
			return []Source{
				{Name: "ok", URL: okSrv.URL, Format: "openai", Class: ClassAITraining},
				{Name: "fail", URL: failSrv.URL, Format: "openai", Class: ClassAITraining},
			}
		},
	})

	if err := r.RunOnce(context.Background()); err != nil {
		t.Fatalf("RunOnce: %v", err)
	}
	if mx.RefreshTotal.Snapshot()["ok_partial"] != 1 {
		t.Errorf("expected ok_partial=1, got snapshot=%v", mx.RefreshTotal.Snapshot())
	}
	if mx.RefreshTotal.Snapshot()["ok"] != 0 {
		t.Errorf("expected ok=0 (one source failed), got snapshot=%v", mx.RefreshTotal.Snapshot())
	}
}

// --- Per-source max-entries cap --------------------------------------

func TestParseOpenAI_RespectsMaxEntriesCap(t *testing.T) {
	// Generate a payload bigger than MaxEntriesPerSource; parser
	// should stop early. Use unique /32 host routes across 10.0.0.0/8
	// to span the 200k entries comfortably (16M slots available).
	var b strings.Builder
	b.WriteString(`{"prefixes":[`)
	target := MaxEntriesPerSource + 100
	for i := 0; i < target; i++ {
		if i > 0 {
			b.WriteString(",")
		}
		a := (i >> 16) & 0xff
		bo := (i >> 8) & 0xff
		c := i & 0xff
		fmt.Fprintf(&b, `{"ipv4Prefix":"10.%d.%d.%d/32"}`, a, bo, c)
	}
	b.WriteString(`]}`)
	nets, err := ParseSource("openai", strings.NewReader(b.String()))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(nets) != MaxEntriesPerSource {
		t.Errorf("expected exactly MaxEntriesPerSource=%d entries, got %d",
			MaxEntriesPerSource, len(nets))
	}
}
