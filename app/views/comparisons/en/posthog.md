---
competitor: "PostHog"
competitor_url: "https://posthog.com"
slug: posthog
title: "mcp-analytics vs PostHog (2026)"
description: "PostHog is the product-analytics suite with web analytics included. We're focused web analytics, MCP-native. Different tools, different jobs."
date: 2026-05-19
verdict_us: "Focused web analytics, MCP-native. You ask in chat, you get an answer. 23 tools. Privacy-first, EU-hosted, cookieless in strict mode. Best for content sites and indie SaaS without product-analytics needs."
verdict_them: "Product-analytics suite. Session replay, feature flags, experiments, surveys, plus web analytics as one of many features. Best for B2B SaaS with paid acquisition and a need for end-to-end user-behavior analytics."
table:
  - feature: "Product scope"
    us: "Web analytics only."
    them: "Product analytics + web analytics + session replay + feature flags + experiments + surveys + LLM observability."
  - feature: "Price entry"
    us: "Free 100k hits/mo.\n€19/mo for 10M hits."
    them: "Free up to 1M product events, 5k recordings, 1M feature flag requests/mo.\nUsage-based after that."
  - feature: "MCP server"
    us: "Yes, primary interface. 23 tools."
    them: "Yes (announced 2024). Tools for cohorts, feature flags, etc."
  - feature: "Dashboard UI"
    us: "None."
    them: "Yes, comprehensive."
  - feature: "Open source"
    us: "Proprietary."
    them: "Yes, MIT (self-hostable Hobby tier free)."
  - feature: "EU hosting"
    us: "Hetzner Falkenstein (Germany)."
    them: "EU and US Cloud regions; self-host wherever."
  - feature: "Cookieless"
    us: "Yes in strict mode (no persistent ID at all)."
    them: "Cookies by default; cookieless mode available."
  - feature: "Session replay"
    us: "No."
    them: "Yes."
  - feature: "Feature flags / experiments"
    us: "No."
    them: "Yes, core part of the product."
  - feature: "AI crawler / bot taxonomy"
    us: "8 traffic classes incl. ai_user_action, ai_crawler."
    them: "Bots filtered as part of standard cleanup."
---

PostHog and mcp-analytics aren't really competitors in the strict sense. PostHog is a product-analytics suite that happens to include web analytics. We're focused web analytics with an MCP primary interface. Different jobs, different buyers. The honest comparison:

## What PostHog actually is

PostHog is an "all-in-one product analytics platform":

- **Product analytics** (events, funnels, cohorts, retention)
- **Web analytics** (the part that overlaps with us)
- **Session replay** (record user sessions, watch them back)
- **Feature flags** (gradual rollouts, kill switches)
- **A/B testing / experiments**
- **Surveys** (in-product NPS, custom)
- **LLM observability** (newer, for AI app developers)

That's a lot. PostHog the company is hundreds of people, hundreds of millions of dollars in funding, and shipping features across all of those surfaces.

mcp-analytics does one of those things (web analytics) with one differentiation (MCP primary interface). We are not trying to be PostHog.

## When PostHog is genuinely the right answer

**You're a B2B SaaS company.** PostHog's home turf. Funnels from signup to conversion to expansion, cohort retention, feature-flag-driven rollouts, A/B tests on your pricing page. If your job has the word "growth" in it, PostHog is your tool, not us.

**You need session replay.** Watching users get confused on a checkout flow is genuinely useful, and PostHog does it well. We have zero of that.

**You need feature flags and experiments.** Same answer.

**You're building an AI app and want LLM observability.** PostHog has shipped LLM observability features specifically for AI app developers. We have not.

**You want one tool for everything.** PostHog's pitch is consolidation. Fewer SaaS bills, fewer SSO logins, one schema for product events. If "I want one place for all this stuff" is your goal, PostHog wins by definition.

**You want open source / self-host.** PostHog is MIT-licensed; you can self-host. We're proprietary.

## When we're genuinely better

**You don't need product analytics.** This is the honest fork. If your site is content (a blog, a landing page, a newsletter, a docs site) or a tool with no user-funnel-conversion-flow worth modeling, PostHog is overkill. You'll log in, see ten tabs of features you don't use, set up funnels you don't need, and pay for storage on event data you're not querying. We're scoped to "how is my site doing?" and answer that question fast.

**You want the chat interface.** PostHog shipped an MCP server in 2024 and it's improving. But PostHog's tool catalog is product-analytics-shaped (cohorts, feature flags, experiments), not web-analytics-shaped. Our 23 MCP tools are designed end-to-end for the web-analytics workflow (`top_pages`, `top_referrers`, `traffic_class_breakdown`, `compare_periods`) and the prompts that reach them work better. If your only question is "how did mysite.com do last week?", asking PostHog gives you a longer answer than asking us.

**You want strict cookieless tracking with no persistent visitor ID.** Our strict mode hashes (daily-rotating salt + site salt + IP + UA + site ID) without any cookie or persistent identifier. Visitor IDs are literally zero. PostHog supports a cookieless mode but the default is cookies; opting in requires configuration and the cookieless mode still generates pseudonymous IDs in some configurations.

**You want explicit AI-crawler breakdown.** We classify traffic into eight buckets including `ai_crawler` (GPTBot, ClaudeBot, etc.) and `ai_user_action` (Claude/ChatGPT fetching for a user). PostHog filters bots as standard data hygiene; you don't see the AI crawler share.

**You want EU-hosted with no US infrastructure path.** PostHog has an EU region. We're EU only.

## On price

Both have generous free tiers, but they're different shapes. PostHog free is 1M product events, 5k recordings, 1M flag requests, etc. A bunch of buckets. Ours is 100k hits/month, unlimited sites.

For a content site that doesn't generate product events or session recordings, PostHog free is structurally more than you need. Our free maps more directly to your actual usage. For a B2B SaaS that has 1M events but only 50k pageviews, PostHog free is the right shape.

At paid pricing, PostHog is usage-based across multiple meters. We're €19/month for 10M hits, flat (€1 per additional 1M).

## A reasonable workflow: use both

A real pattern many SaaS founders use: PostHog for product analytics (signup funnel, feature flag rollouts, experiments) plus mcp-analytics for content/marketing-site analytics. Reason: the marketing site doesn't benefit from session replay or funnels, but does benefit from cheap headroom and a chat workflow. PostHog has incrementally less value-per-event on a marketing site; we have more.

If you only have one site to track and it's your product, just use PostHog. If you have a product *and* a marketing site, consider splitting.

## What's not a real difference

- Both privacy-first (in their respective modes).
- Both EU-host-capable.
- Both have MCP servers.
- Both have decent free tiers (different shapes).

## Try it

If you're already on PostHog and happy: stay. We're not trying to replace it.

If you have a content/marketing site that doesn't need PostHog's full surface: [sign up free](/), add our snippet, ask Claude how it's going. €19/month later when you outgrow the free tier feels different from PostHog's usage-meter at scale.
