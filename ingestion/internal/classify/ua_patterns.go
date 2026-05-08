package classify

import "strings"

// UA-pattern → Class. Keys are lowercased substrings; we match by
// strings.Contains so any UA containing the marker hits.
//
// Curation source (May 2026): merged from
//   - ai-robots-txt/ai.robots.txt (community-curated AI crawler list)
//   - Anthropic's own bot doc (support.anthropic.com)
//   - OpenAI's published list (platform.openai.com/docs/bots)
//   - Cloudflare Radar AI Crawlers section
//   - manual additions from production logs
//
// Order does NOT matter — the first matching pattern wins, but every
// marker should be specific enough that conflicts are exceptional. If
// two patterns ever match the same UA, classifyUA returns the more
// specific one first by iterating over the slice (Go's built-in map
// iteration is randomized so we use a slice of pairs instead).
//
// Refresh process: roughly every 1-2 months, diff against the
// ai.robots.txt repo and add new entries here. The .github/workflows
// schema-check workflow alerts us when this list is meaningfully out
// of sync with the live JSONs.

type uaPattern struct {
	marker string // lowercased substring to match against UA
	class  Class
}

// uaPatterns is the curated UA → class table.
//
// Order in this list matters because we return on first match. Put more
// specific markers above more general ones (e.g. "claude-user" before
// "claude" before "claudebot" — actually "claudebot" must come before
// "claude" because both contain "claude").
//
// Convention: lowercase only, no regex, no anchors. Plain substring.
var uaPatterns = []uaPattern{
	// --- ai_user_action: live human-driven AI browsing ---------------
	// A human is chatting with the assistant and the assistant fetched
	// the page on their behalf. These are real human attention, just
	// AI-mediated.
	{"chatgpt-user", ClassAIUserAction},
	{"oai-searchgpt", ClassAIUserAction},
	{"claude-user", ClassAIUserAction},
	{"claude-web", ClassAIUserAction}, // legacy Anthropic UA, predates the user/bot split
	{"perplexity-user", ClassAIUserAction},
	{"copilot-user", ClassAIUserAction}, // Microsoft Copilot live-fetches
	{"meta-externalfetcher", ClassAIUserAction},
	{"mistralai-user", ClassAIUserAction}, // Mistral live-fetch (-user suffix convention)

	// --- ai_search: AI search-engine indexers ------------------------
	// They build an index used to answer queries with citations. Closer
	// to "search_index" than "ai_training" but we keep them separate so
	// AIEO-aware customers can target them specifically.
	{"oai-searchbot", ClassAISearch},
	{"perplexitybot", ClassAISearch},
	{"youbot", ClassAISearch},
	{"phindbot", ClassAISearch},

	// --- ai_training: crawlers for LLM training data -----------------
	// Their fetches end up in training corpora, not in real-time answers.
	// Key targets for "should I block this in robots.txt?" decisions.
	{"gptbot", ClassAITraining},
	{"claudebot", ClassAITraining},
	{"anthropic-ai", ClassAITraining}, // older Anthropic crawler UA
	{"ccbot", ClassAITraining},        // Common Crawl, used by many model trainers
	{"bytespider", ClassAITraining},   // ByteDance / Doubao
	{"diffbot", ClassAITraining},
	{"meta-externalagent", ClassAITraining}, // distinct from -externalfetcher
	{"facebookbot", ClassAITraining},
	{"google-extended", ClassAITraining}, // Gemini training opt-out signal
	{"applebot-extended", ClassAITraining},
	{"cohere-ai", ClassAITraining},
	{"cohere-training-data-crawler", ClassAITraining},
	{"omgili", ClassAITraining},
	{"webzbot", ClassAITraining},
	{"timpibot", ClassAITraining},
	{"ai2bot", ClassAITraining},
	{"awariobot", ClassAITraining},
	{"omgilibot", ClassAITraining},

	// --- search_index: classic web search indexers -------------------
	// Order: more specific first ("googleother" before "googlebot",
	// "applebot" before generic "apple").
	{"googleother", ClassSearchIndex},
	{"googlebot", ClassSearchIndex},
	{"adsbot-google", ClassSearchIndex},
	{"mediapartners-google", ClassSearchIndex},
	{"bingbot", ClassSearchIndex},
	{"applebot", ClassSearchIndex},
	{"duckduckbot", ClassSearchIndex},
	{"yandex", ClassSearchIndex},
	{"baiduspider", ClassSearchIndex},
	{"naver", ClassSearchIndex},
	{"seznambot", ClassSearchIndex},
	{"qwantbot", ClassSearchIndex},

	// --- social_unfurl: link previews / social cards -----------------
	{"slackbot", ClassSocialUnfurl},
	{"facebookexternalhit", ClassSocialUnfurl},
	{"twitterbot", ClassSocialUnfurl},
	{"linkedinbot", ClassSocialUnfurl},
	{"discordbot", ClassSocialUnfurl},
	{"telegrambot", ClassSocialUnfurl},
	{"whatsapp", ClassSocialUnfurl},
	{"redditbot", ClassSocialUnfurl},
	{"pinterest", ClassSocialUnfurl},
	{"embedly", ClassSocialUnfurl},
	{"bingpreview", ClassSocialUnfurl},
	{"skypeuripreview", ClassSocialUnfurl},
	{"vkshare", ClassSocialUnfurl},

	// --- scanner: security / uptime / synthetic / dev tooling --------
	// Anything that is "we are testing your site" rather than "we are a
	// person reading your site" or "we are an indexer".
	{"pingdom", ClassScanner},
	{"uptimerobot", ClassScanner},
	{"gtmetrix", ClassScanner},
	{"lighthouse", ClassScanner},
	{"pagespeed", ClassScanner},
	{"chrome-lighthouse", ClassScanner},
	{"censys", ClassScanner},
	{"shodan", ClassScanner},
	{"semrushbot", ClassScanner},
	{"semrush", ClassScanner},
	{"ahrefsbot", ClassScanner},
	{"ahrefs", ClassScanner},
	{"mj12bot", ClassScanner},
	{"dotbot", ClassScanner},
	{"barkrowler", ClassScanner},
	{"dataforseobot", ClassScanner},
	{"petalbot", ClassScanner},
	{"headlesschrome", ClassScanner},
	{"phantomjs", ClassScanner},
	{"selenium", ClassScanner},
	{"puppeteer", ClassScanner},
	{"playwright", ClassScanner},
	{"http_request2", ClassScanner},

	// --- bot_other catch-all generics --------------------------------
	// Tools and fetchers that aren't really "scanners" but are clearly
	// not human browsers either.
	{"python-requests", ClassBotOther},
	{"python-urllib", ClassBotOther},
	{"curl/", ClassBotOther},
	{"wget/", ClassBotOther},
	{"go-http-client", ClassBotOther},
	{"okhttp/", ClassBotOther},
	{"apache-httpclient", ClassBotOther},
	{"java/", ClassBotOther},
	{"http.rb/", ClassBotOther},
	{"httpx", ClassBotOther},
	{"aiohttp", ClassBotOther},
	{"axios/", ClassBotOther},
	{"node-fetch", ClassBotOther},
	{"undici", ClassBotOther},
	{"got (", ClassBotOther},

	// --- generic tail markers (last resort) --------------------------
	// These are intentionally LAST because they're broad. A UA matching
	// "spider" but also "googlebot" already returned ClassSearchIndex
	// above before we get here.
	{"crawl", ClassBotOther},
	{"spider", ClassBotOther},
	{"slurp", ClassBotOther},
	{"bot", ClassBotOther},
}

// classifyUA returns the Class implied by the User-Agent string, or
// "" if no marker matched. Caller decides what "" means (typically
// ClassUser if the rest of the signals also look human, otherwise
// the IP/heuristic layer takes over).
func classifyUA(userAgent string) Class {
	if userAgent == "" {
		// Empty UA used to be treated as bot in Phase 1. We keep that
		// behavior but as the more specific bot_other rather than the
		// no-information case.
		return ClassBotOther
	}
	lo := strings.ToLower(userAgent)
	for _, p := range uaPatterns {
		if strings.Contains(lo, p.marker) {
			return p.class
		}
	}
	return ""
}
