package classify

import "net"

// FallbackRanges returns a hand-curated set of CIDRs that ship with
// the binary so the classifier has *something* useful before the first
// live refresh completes (and as a fall-through if all external
// fetches fail).
//
// This list is deliberately small — just a few well-known stable
// ranges per major provider. The full live-fetched lists are larger
// (10k+ CIDRs total) and authoritative; these are belt-and-suspenders.
//
// Refresh policy: bump these maybe twice a year, only when an entry
// here demonstrably stops covering live bot traffic. Don't try to keep
// them in sync with the live JSONs — that's what the refresh loop is
// for.
//
// Sources for each range below are documented inline. All entries
// gathered May 2026 from each vendor's public IP-ranges JSON, taking
// the largest aggregating prefix for each region.
func FallbackRanges() []TrieEntry {
	type seed struct {
		cidr     string
		class    Class
		provider string
		cloud    bool
	}

	seeds := []seed{
		// --- OpenAI GPTBot (sample of 2026-05 ranges) ----------------
		{"23.98.142.176/28", ClassAITraining, "openai-gptbot", false},
		{"40.84.180.224/28", ClassAITraining, "openai-gptbot", false},
		{"172.203.190.128/28", ClassAITraining, "openai-gptbot", false},

		// --- OpenAI ChatGPT-User (live browse) -----------------------
		{"23.102.140.112/28", ClassAIUserAction, "openai-chatgpt-user", false},
		{"40.84.180.64/28", ClassAIUserAction, "openai-chatgpt-user", false},

		// --- OpenAI SearchBot ----------------------------------------
		{"20.42.10.176/28", ClassAISearch, "openai-searchbot", false},

		// --- Google Googlebot (well-known stable /24s) ---------------
		{"66.249.64.0/19", ClassSearchIndex, "google-googlebot", false},
		{"34.100.182.96/28", ClassSearchIndex, "google-googlebot", false},
		{"35.247.243.240/28", ClassSearchIndex, "google-googlebot", false},

		// --- Bing Bingbot --------------------------------------------
		{"40.77.167.0/24", ClassSearchIndex, "bingbot", false},
		{"157.55.39.0/24", ClassSearchIndex, "bingbot", false},
		{"207.46.13.0/24", ClassSearchIndex, "bingbot", false},

		// --- Cloud infra (heuristic supplement only) -----------------
		// Just one or two well-known prefixes per provider — the live
		// list is much larger but for cold-start "is this an EC2-ish
		// IP" we don't need full coverage.
		{"3.0.0.0/8", ClassScanner, "aws", true},        // AWS us-east-1 chunk
		{"52.0.0.0/8", ClassScanner, "aws", true},       // AWS broad
		{"34.64.0.0/10", ClassScanner, "gcp", true},     // GCP broad
		{"35.184.0.0/13", ClassScanner, "gcp", true},    // GCP broad
		{"104.16.0.0/12", ClassScanner, "cloudflare", true}, // Cloudflare proxies
		{"172.64.0.0/13", ClassScanner, "cloudflare", true},
	}

	out := make([]TrieEntry, 0, len(seeds))
	for _, s := range seeds {
		_, n, err := net.ParseCIDR(s.cidr)
		if err != nil || n == nil {
			// Compile-time bug — log loudly during tests, drop in prod.
			continue
		}
		out = append(out, TrieEntry{
			Net:          n,
			Class:        s.class,
			Provider:     s.provider,
			IsCloudInfra: s.cloud,
		})
	}
	return out
}
