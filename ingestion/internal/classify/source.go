package classify

// Source describes one external IP-range JSON endpoint plus the
// classification it implies. The refresh loop iterates over Sources(),
// fetches each URL, and inserts the parsed CIDRs into the trie tagged
// with the Source's Class + Provider.
//
// Provider exists separately from Class because two distinct sources
// may map to the same Class (e.g. OpenAI/GPTBot and Anthropic/ClaudeBot
// both → ClassAITraining) but we want to be able to attribute hits to
// the specific provider when answering questions like "how many GPTBot
// vs ClaudeBot fetches did I see?". Provider is stored in the trie
// entry but not currently exposed in the traffic_class column — it can
// be promoted to its own column later if we ever need that breakdown.

type Source struct {
	Name     string // human-readable label, used in logs + metrics
	URL      string // public JSON endpoint
	Format   string // "openai", "google", "bing", "aws", "gcp", "azure", "cloudflare"
	Class    Class  // class to assign to IPs from this source
	Provider string // free-form provider tag ("openai", "google", ...)

	// IsCloudInfra marks this source as "cloud-provider IP space, not
	// crawler-specific" — i.e. AWS/GCP/Azure/CF. These ranges are huge
	// and overlap with legitimate human traffic (anyone running a VPN
	// out of EC2). The classifier uses them ONLY as a heuristic
	// supplement: if the UA already matched a specific bot pattern we
	// trust that; if the UA looks like generic Chrome we DO NOT
	// classify cloud-IP traffic as scanner unless other signals agree.
	// See heuristic.go for the rules.
	IsCloudInfra bool
}

// Sources returns the canonical list of external IP-range endpoints.
// Used by both the refresh loop (live fetch) and the daily schema-check
// GitHub workflow.
//
// Adding a source:
//   1. Append here with appropriate Class/Provider
//   2. Add a parser in parsers.go if Format isn't already supported
//   3. Optionally add a snapshot to fallback_ranges.go for cold-start
func Sources() []Source {
	return []Source{
		// --- OpenAI: 3 distinct UAs, 3 distinct ranges -----------------
		{
			Name:     "openai-gptbot",
			URL:      "https://openai.com/gptbot.json",
			Format:   "openai",
			Class:    ClassAITraining,
			Provider: "openai-gptbot",
		},
		{
			Name:     "openai-searchbot",
			URL:      "https://openai.com/searchbot.json",
			Format:   "openai",
			Class:    ClassAISearch,
			Provider: "openai-searchbot",
		},
		{
			Name:     "openai-chatgpt-user",
			URL:      "https://openai.com/chatgpt-user.json",
			Format:   "openai",
			Class:    ClassAIUserAction,
			Provider: "openai-chatgpt-user",
		},

		// --- Google ----------------------------------------------------
		// Google moved their canonical endpoint in March 2026 (the old
		// /search/apis/ipranges/googlebot.json URL went 410 ~8 days
		// after announcement — see ai-crawler-schema-check workflow).
		// Use the new /crawling/ipranges/ paths.
		{
			Name:     "google-googlebot",
			URL:      "https://developers.google.com/static/search/apis/ipranges/googlebot.json",
			Format:   "google",
			Class:    ClassSearchIndex,
			Provider: "google-googlebot",
		},
		{
			Name:     "google-special-crawlers",
			URL:      "https://developers.google.com/static/search/apis/ipranges/special-crawlers.json",
			Format:   "google",
			Class:    ClassSearchIndex,
			Provider: "google-special",
		},
		{
			Name:     "google-user-triggered",
			URL:      "https://developers.google.com/static/search/apis/ipranges/user-triggered-fetchers-google.json",
			Format:   "google",
			Class:    ClassAIUserAction, // Gemini live-fetch falls here
			Provider: "google-user-triggered",
		},

		// --- Bing ------------------------------------------------------
		{
			Name:     "bing-bingbot",
			URL:      "https://www.bing.com/toolbox/bingbot.json",
			Format:   "bing",
			Class:    ClassSearchIndex,
			Provider: "bingbot",
		},

		// --- Cloud-infra ranges (heuristic supplement only) ------------
		// These are large and not classification-authoritative — see
		// IsCloudInfra docs above.
		{
			Name:         "aws-ip-ranges",
			URL:          "https://ip-ranges.amazonaws.com/ip-ranges.json",
			Format:       "aws",
			Class:        ClassScanner, // tentative; heuristic decides
			Provider:     "aws",
			IsCloudInfra: true,
		},
		{
			Name:         "gcp-cloud",
			URL:          "https://www.gstatic.com/ipranges/cloud.json",
			Format:       "gcp",
			Class:        ClassScanner,
			Provider:     "gcp",
			IsCloudInfra: true,
		},
		{
			Name:         "cloudflare-ips-v4",
			URL:          "https://www.cloudflare.com/ips-v4/",
			Format:       "cloudflare",
			Class:        ClassScanner,
			Provider:     "cloudflare",
			IsCloudInfra: true,
		},
		{
			Name:         "cloudflare-ips-v6",
			URL:          "https://www.cloudflare.com/ips-v6/",
			Format:       "cloudflare",
			Class:        ClassScanner,
			Provider:     "cloudflare",
			IsCloudInfra: true,
		},
		// Azure deliberately omitted — they rotate the download URL
		// monthly via their UI ("download.microsoft.com/download/<guid>")
		// which makes hardcoding it brittle. Skipped until someone
		// invests in scraping the manifest page. AWS+GCP+CF cover the
		// majority of cloud-hosted bot traffic anyway.
	}
}
