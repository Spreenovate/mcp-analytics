# Static shell for /ai-crawler-index. The strategy doc describes this
# page as the weekly-update moat content once we have ≥50 paying Pro
# customers feeding aggregate data. Pre-launch, we render an N=1 demo
# (mcp-analytics.com's own traffic, with a clear disclaimer) so the
# page exists, ranks for the relevant keywords, and the pipeline is
# obvious to readers.
#
# When the data pipeline lands, swap the @entries / @summary / @last_updated
# hashes for live ClickHouse query results — view doesn't change.
class AiCrawlerIndexController < ApplicationController
  def show
    @last_updated = Date.new(2026, 5, 19)
    response.set_header("Last-Modified", @last_updated.to_time(:utc).httpdate)
    response.set_header("Cache-Control", "public, max-age=3600")
    @sample_size_sites = 1
    # Total observed hits (humans + ai_user_action + crawlers + bots),
    # last 30 days, on mcp-analytics.com itself. Crawler hits sum to
    # 6,094 below, which is 6.7% of this denominator.
    @sample_size_hits = 90_955
    @summary = {
      total_hits_observed: 90_955,
      window_days: 30,
      crawler_share_pct: 6.7,
      ai_user_action_share_pct: 9.7
    }
    # share_pct on each row is share of CRAWLER traffic, not of all
    # traffic. Sums to 100% across the table. Headline crawler share
    # (6.7% above) is the share of crawlers in TOTAL traffic.
    snap = @last_updated.strftime("%B %Y")
    @entries = [
      { bot: "GPTBot",            operator: "OpenAI",       hits: 2_847, share_pct: 46.7, wow_pct: 18, robots_token: "GPTBot",            note: "Training + ChatGPT browsing. Aggressive in #{snap}." },
      { bot: "ClaudeBot",         operator: "Anthropic",    hits: 1_612, share_pct: 26.5, wow_pct: 22, robots_token: "ClaudeBot",         note: "Training crawler. Polite, respects crawl-delay." },
      { bot: "PerplexityBot",     operator: "Perplexity",   hits:   802, share_pct: 13.2, wow_pct: 30, robots_token: "PerplexityBot",     note: "Fastest-growing AI crawler in the current snapshot. Answer-grounding focus." },
      { bot: "OAI-SearchBot",     operator: "OpenAI",       hits:   412, share_pct:  6.8, wow_pct: 12, robots_token: "OAI-SearchBot",     note: "ChatGPT Search indexing. Separate token from GPTBot." },
      { bot: "CCBot",             operator: "Common Crawl", hits:   148, share_pct:  2.4, wow_pct: -5, robots_token: "CCBot",             note: "Feeds many downstream LLMs. Monthly bulk crawl." },
      { bot: "Claude-Web",        operator: "Anthropic",    hits:    92, share_pct:  1.5, wow_pct:  8, robots_token: "Claude-Web",        note: "Claude's user-initiated web fetch. Different from ClaudeBot." },
      { bot: "Bytespider",        operator: "Bytedance",    hits:    71, share_pct:  1.2, wow_pct: -20, robots_token: "Bytespider",       note: "Powers Doubao + TikTok search. Heavy traffic on some sites." },
      { bot: "Applebot-Extended", operator: "Apple",        hits:    48, share_pct:  0.8, wow_pct: 15, robots_token: "Applebot-Extended", note: "Apple Intelligence training opt-out signal." },
      { bot: "FacebookBot",       operator: "Meta",         hits:    32, share_pct:  0.5, wow_pct:  3, robots_token: "FacebookBot",       note: "Meta AI. Lower volume than GPT-class." },
      { bot: "cohere-ai",         operator: "Cohere",       hits:    19, share_pct:  0.3, wow_pct:  0, robots_token: "cohere-ai",         note: "Cohere's training fetch. Niche but present." },
      { bot: "DuckAssistBot",     operator: "DuckDuckGo",   hits:    11, share_pct:  0.2, wow_pct: 25, robots_token: "DuckAssistBot",     note: "DuckDuckGo AI Assist. Just appeared in our logs this snapshot." }
    ]
  end
end
