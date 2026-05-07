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

// --- UA-pattern matching ---------------------------------------------

func TestClassifyUA_KnownPatterns(t *testing.T) {
	cases := []struct {
		ua   string
		want Class
	}{
		// ai_user_action
		{"Mozilla/5.0 ChatGPT-User/1.0", ClassAIUserAction},
		{"Mozilla/5.0 Claude-User/1.0", ClassAIUserAction},
		{"Mozilla/5.0 perplexity-user/2.0", ClassAIUserAction},
		// ai_search
		{"OAI-SearchBot/1.0", ClassAISearch},
		{"PerplexityBot/1.0 +https://perplexity.ai/perplexitybot", ClassAISearch},
		// ai_training
		{"Mozilla/5.0 (compatible; GPTBot/1.0; +https://openai.com)", ClassAITraining},
		{"ClaudeBot/1.0 +mailto:support@anthropic.com", ClassAITraining},
		{"Mozilla/5.0 (compatible; Bytespider; ...)", ClassAITraining},
		{"CCBot/2.0 +https://commoncrawl.org/bot.html", ClassAITraining},
		// search_index
		{"Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", ClassSearchIndex},
		{"Mozilla/5.0 (compatible; bingbot/2.0)", ClassSearchIndex},
		{"DuckDuckBot/1.0", ClassSearchIndex},
		{"Mozilla/5.0 (compatible; YandexBot/3.0)", ClassSearchIndex},
		// social_unfurl
		{"Slackbot-LinkExpanding/1.0", ClassSocialUnfurl},
		{"facebookexternalhit/1.1", ClassSocialUnfurl},
		{"Twitterbot/1.0", ClassSocialUnfurl},
		{"LinkedInBot/1.0", ClassSocialUnfurl},
		// scanner
		{"Mozilla/5.0 (compatible; Pingdom.com_bot)", ClassScanner},
		{"UptimeRobot/2.0", ClassScanner},
		{"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0", ClassScanner},
		{"AhrefsBot/7.0", ClassScanner},
		// bot_other
		{"curl/7.88.0", ClassBotOther},
		{"python-requests/2.28.0", ClassBotOther},
		{"Go-http-client/1.1", ClassBotOther},
		{"", ClassBotOther},
	}
	for _, c := range cases {
		got := classifyUA(c.ua)
		if got != c.want {
			t.Errorf("classifyUA(%q): got %q want %q", c.ua, got, c.want)
		}
	}
}

func TestClassifyUA_RealBrowsersDontMatch(t *testing.T) {
	humans := []string{
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
	}
	for _, ua := range humans {
		got := classifyUA(ua)
		if got != "" {
			t.Errorf("classifyUA(%q): expected unmatched (empty), got %q", ua, got)
		}
	}
}

// --- Parser tests ----------------------------------------------------

func TestParseOpenAI_Schema(t *testing.T) {
	body := `{"creationTime":"2026-01-01","prefixes":[
		{"ipv4Prefix":"23.98.142.176/28"},
		{"ipv6Prefix":"2603:1030:7::/48"}
	]}`
	nets, err := ParseSource("openai", strings.NewReader(body))
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if len(nets) != 2 {
		t.Fatalf("got %d nets, want 2", len(nets))
	}
	if nets[0].String() != "23.98.142.176/28" {
		t.Errorf("net[0]: got %q", nets[0].String())
	}
}

func TestParseAWS_Schema(t *testing.T) {
	body := `{
		"syncToken":"123","createDate":"now",
		"prefixes":[{"ip_prefix":"3.0.0.0/8","region":"us-east-1","service":"AMAZON"}],
		"ipv6_prefixes":[{"ipv6_prefix":"2400:6500::/40"}]
	}`
	nets, err := ParseSource("aws", strings.NewReader(body))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(nets) != 2 {
		t.Fatalf("got %d nets, want 2", len(nets))
	}
}

func TestParseCloudflare_Plaintext(t *testing.T) {
	body := "# header comment\n104.16.0.0/12\n172.64.0.0/13\n\n# trailing\n"
	nets, err := ParseSource("cloudflare", strings.NewReader(body))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(nets) != 2 {
		t.Fatalf("got %d nets, want 2", len(nets))
	}
}

func TestParseSource_UnknownFormat(t *testing.T) {
	_, err := ParseSource("not-a-format", strings.NewReader("{}"))
	if err == nil {
		t.Error("expected error for unknown format")
	}
}

// --- Trie lookup -----------------------------------------------------

func TestTrieLookup_Hit(t *testing.T) {
	_, n, _ := net.ParseCIDR("23.98.142.176/28")
	trie := NewTrie([]TrieEntry{
		{Net: n, Class: ClassAITraining, Provider: "openai-gptbot"},
	})
	got, prov, ok := trie.Lookup(net.ParseIP("23.98.142.180"))
	if !ok {
		t.Fatal("expected lookup to hit")
	}
	if got != ClassAITraining {
		t.Errorf("class: got %q want %q", got, ClassAITraining)
	}
	if prov != "openai-gptbot" {
		t.Errorf("provider: got %q", prov)
	}
}

func TestTrieLookup_Miss(t *testing.T) {
	trie := NewTrie(FallbackRanges())
	if _, _, ok := trie.Lookup(net.ParseIP("198.51.100.1")); ok {
		t.Error("expected lookup to miss for TEST-NET-2 IP")
	}
}

func TestTrieLookup_PrefersSpecificOverCloud(t *testing.T) {
	// A specific OpenAI /28 nested inside a broad AWS /8 — should
	// classify as ai_training, not scanner-from-aws.
	_, awsNet, _ := net.ParseCIDR("3.0.0.0/8")
	_, openaiNet, _ := net.ParseCIDR("3.5.140.176/28")
	trie := NewTrie([]TrieEntry{
		{Net: awsNet, Class: ClassScanner, Provider: "aws", IsCloudInfra: true},
		{Net: openaiNet, Class: ClassAITraining, Provider: "openai-gptbot"},
	})
	got, prov, ok := trie.Lookup(net.ParseIP("3.5.140.180"))
	if !ok {
		t.Fatal("expected hit")
	}
	if got != ClassAITraining {
		t.Errorf("preferred-class: got %q want %q (provider=%q)",
			got, ClassAITraining, prov)
	}
}

// --- Classifier integration -----------------------------------------

func TestClassifier_UAOnly_NoIPInfo(t *testing.T) {
	c := NewClassifier(&AtomicLookup{})
	got := c.Classify("Mozilla/5.0 (compatible; Googlebot/2.1)", nil)
	if got != ClassSearchIndex {
		t.Errorf("got %q want %q", got, ClassSearchIndex)
	}
}

func TestClassifier_HumanUA_NoIPInfo_DefaultsToUser(t *testing.T) {
	c := NewClassifier(&AtomicLookup{})
	humanUA := "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Chrome/120.0.0.0 Safari/605.1.15"
	got := c.Classify(humanUA, net.ParseIP("198.51.100.1"))
	if got != ClassUser {
		t.Errorf("got %q want %q", got, ClassUser)
	}
}

func TestClassifier_SpoofedUA_FromCloudIP_DemotedToBotOther(t *testing.T) {
	// UA says GPTBot, IP is in a known cloud range that's NOT a
	// vendor-specific OpenAI prefix → must demote to bot_other.
	_, awsNet, _ := net.ParseCIDR("3.0.0.0/8")
	lookup := &AtomicLookup{}
	lookup.Store(NewTrie([]TrieEntry{
		{Net: awsNet, Class: ClassScanner, Provider: "aws", IsCloudInfra: true},
	}))
	c := NewClassifier(lookup)
	got := c.Classify("GPTBot/1.0 (openai.com)", net.ParseIP("3.99.99.99"))
	if got != ClassBotOther {
		t.Errorf("spoofed-UA-from-cloud: got %q want %q", got, ClassBotOther)
	}
}

func TestClassifier_GenericBrowserFromCloud_HeuristicScanner(t *testing.T) {
	_, awsNet, _ := net.ParseCIDR("3.0.0.0/8")
	lookup := &AtomicLookup{}
	lookup.Store(NewTrie([]TrieEntry{
		{Net: awsNet, Class: ClassScanner, Provider: "aws", IsCloudInfra: true},
	}))
	c := NewClassifier(lookup)
	got := c.Classify(
		"Mozilla/5.0 (Macintosh) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		net.ParseIP("3.42.99.99"))
	if got != ClassScanner {
		t.Errorf("generic-browser-from-cloud heuristic: got %q want %q", got, ClassScanner)
	}
}

func TestClassifier_RealHumanFromResidential_Stays_User(t *testing.T) {
	c := NewClassifier(&AtomicLookup{})
	c.ipLookupFn = func(ip net.IP) (Class, string, bool) { return "", "", false }
	c.ipIsCloudFn = func(ip net.IP) bool { return false }
	got := c.Classify(
		"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
		net.ParseIP("82.165.10.10"))
	if got != ClassUser {
		t.Errorf("got %q want %q", got, ClassUser)
	}
}

func TestClassifier_NoUA_ButIPMatchesVendor(t *testing.T) {
	_, openaiNet, _ := net.ParseCIDR("23.98.142.176/28")
	lookup := &AtomicLookup{}
	lookup.Store(NewTrie([]TrieEntry{
		{Net: openaiNet, Class: ClassAITraining, Provider: "openai-gptbot"},
	}))
	c := NewClassifier(lookup)
	got := c.Classify("", net.ParseIP("23.98.142.180"))
	if got != ClassAITraining {
		t.Errorf("got %q want %q", got, ClassAITraining)
	}
}

// --- AllClasses sanity ----------------------------------------------

func TestAllClasses_HasEightDistinctValues(t *testing.T) {
	if len(AllClasses) != 8 {
		t.Errorf("AllClasses has %d entries, want 8", len(AllClasses))
	}
	seen := map[Class]bool{}
	for _, c := range AllClasses {
		if seen[c] {
			t.Errorf("duplicate class %q in AllClasses", c)
		}
		seen[c] = true
	}
}

// --- Refresh integration --------------------------------------------

func TestRefresher_RunOnce_BuildsTrie(t *testing.T) {
	// Stand up a fake HTTP server that responds with OpenAI-shaped JSON.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"prefixes": []map[string]string{
				{"ipv4Prefix": "23.98.142.176/28"},
				{"ipv4Prefix": "23.98.142.192/28"},
			},
		})
	}))
	defer srv.Close()

	mx := NewMetrics()
	target := &AtomicLookup{}
	r := NewRefresher(target, mx, RefreshConfig{
		HTTPTimeout:    2 * time.Second,
		MinShrinkRatio: 0.5,
		SourceFn: func() []Source {
			return []Source{{
				Name:     "fake",
				URL:      srv.URL,
				Format:   "openai",
				Class:    ClassAITraining,
				Provider: "test",
			}}
		},
	})
	if err := r.RunOnce(context.Background()); err != nil {
		t.Fatalf("RunOnce: %v", err)
	}
	got, _, ok := target.Lookup(net.ParseIP("23.98.142.180"))
	if !ok || got != ClassAITraining {
		t.Errorf("lookup after refresh: got %q ok=%v want %q", got, ok, ClassAITraining)
	}
	if mx.RefreshTotal.Snapshot()["ok"] != 1 {
		t.Error("expected refresh_total[ok]=1")
	}
}

func TestRefresher_RejectsShrinkingTrie(t *testing.T) {
	// First fetch returns 4 entries; second fetch returns 1. Sanity-
	// check threshold 0.5 → second should be rejected.
	count := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		count++
		var prefixes []map[string]string
		if count == 1 {
			prefixes = []map[string]string{
				{"ipv4Prefix": "10.1.0.0/24"}, {"ipv4Prefix": "10.2.0.0/24"},
				{"ipv4Prefix": "10.3.0.0/24"}, {"ipv4Prefix": "10.4.0.0/24"},
			}
		} else {
			prefixes = []map[string]string{
				{"ipv4Prefix": "10.1.0.0/24"}, // 1/4 = 0.25, under threshold
			}
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
		t.Fatalf("first run: %v", err)
	}
	first := mx.CIDRsLoaded.Total()
	if first != 4 {
		t.Fatalf("first run loaded %d, want 4", first)
	}

	err := r.RunOnce(context.Background())
	if err == nil {
		t.Fatal("expected second run to be rejected by sanity-check")
	}
	if !strings.Contains(err.Error(), "rejected") {
		t.Errorf("expected rejection message, got: %v", err)
	}
	// Trie should still hold the 4 entries from the first refresh.
	if got := mx.CIDRsLoaded.Total(); got != 4 {
		t.Errorf("CIDRsLoaded after rejected refresh: got %d want 4", got)
	}
}

func TestRefresher_HTTPErrorIsRecorded(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprint(w, "internal error")
	}))
	defer srv.Close()

	mx := NewMetrics()
	target := &AtomicLookup{}
	r := NewRefresher(target, mx, RefreshConfig{
		SourceFn: func() []Source {
			return []Source{{Name: "fake", URL: srv.URL, Format: "openai", Class: ClassAITraining}}
		},
	})
	if err := r.RunOnce(context.Background()); err == nil {
		t.Fatal("expected error from 500 response")
	}
	if mx.RefreshFailedTotal.Snapshot()["fake"] != 1 {
		t.Error("expected refresh_failed_total[fake]=1")
	}
}

// --- Helpers ---------------------------------------------------------

func TestIsHumanIsBot(t *testing.T) {
	if !IsHuman(ClassUser) || !IsHuman(ClassAIUserAction) {
		t.Error("user / ai_user_action should be human")
	}
	if IsHuman(ClassAITraining) || IsHuman(ClassScanner) {
		t.Error("ai_training / scanner should NOT be human")
	}
	if IsBot(ClassUser) || IsBot(ClassAIUserAction) {
		t.Error("user / ai_user_action should NOT be bot")
	}
	if !IsBot(ClassScanner) || !IsBot(ClassAITraining) {
		t.Error("scanner / ai_training should be bot")
	}
}
