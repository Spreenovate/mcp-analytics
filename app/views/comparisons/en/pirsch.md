---
competitor: "Pirsch Analytics"
competitor_url: "https://pirsch.io"
slug: pirsch
title: "mcp-analytics vs Pirsch Analytics (2026)"
description: "Pirsch is the cheapest credible EU-hosted analytics. We're MCP-native. Where each wins, where neither is right."
date: 2026-05-19
hreflang_alt: pirsch
verdict_us: "MCP-native primary interface. Free 100k hits/mo without a card. 8-class bot taxonomy. Server-side SDK on Pro. Best for the Claude/Cursor power-user."
verdict_them: "Cheapest credible EU-hosted analytics with a polished dashboard. Strong AI-referrer channel built in. Best for German-speaking founders who want a clean dashboard and a small bill."
table:
  - feature: "Price entry"
    us: "Free 100k hits/mo, no card.\n€19/mo for 10M hits."
    them: "30-day trial.\n$6/mo Standard tier for 10k pageviews."
  - feature: "Hits at ~$19"
    us: "10,000,000 / month"
    them: "100,000 / month (Plus tier)"
  - feature: "Dashboard UI"
    us: "None. MCP-only."
    them: "Polished dashboard with AI-referrer channel built-in."
  - feature: "MCP server"
    us: "Yes, primary interface. 23 tools."
    them: "No."
  - feature: "EU hosting"
    us: "Hetzner Falkenstein (Germany)."
    them: "Germany-hosted, GDPR-native."
  - feature: "Cookieless"
    us: "Yes (strict mode)."
    them: "Yes by default."
  - feature: "Custom events"
    us: "JS + server-side SDK on Pro."
    them: "JS-based."
  - feature: "AI crawler / referrer tracking"
    us: "8 traffic classes incl. ai_user_action, ai_crawler, verified_search_bot."
    them: "AI-referrer channel (human from ChatGPT/Perplexity). No crawler-side breakdown."
  - feature: "Unlimited sites"
    us: "Yes, all tiers."
    them: "50 sites Standard, more on higher tiers."
  - feature: "Origin: Germany"
    us: "Spreenovate GmbH (Berlin)."
    them: "emvi Software GmbH (Hannover)."
---

Pirsch is the cheapest credible privacy-first analytics tool with EU hosting. They're a small German team, and they've built a tight, fast product. We respect what they've shipped.

Pirsch and mcp-analytics aren't direct substitutes. Different interface bet. Honest case for each:

## Where Pirsch wins

**Price floor.** Pirsch's $6/month Standard tier is the cheapest credible EU-hosted analytics on the market. If you have a personal site with under 10k pageviews/month and want it paid (no card-on-file dependency we have on free tier), Pirsch is cheaper. We're free up to 100k, then €19. For a tiny site, Pirsch wins the dollar-comparison.

**AI-referrer channel.** Pirsch has shipped an "AI" channel in their dashboard that groups referrers from ChatGPT, Perplexity, Claude.ai, etc. Human visitors who clicked through from an AI chat. Useful pre-built filter. We track the same data (in `top_referrers`), but we don't have a UI grouping for it because we don't have a UI. You'd ask in chat "how much of last week's traffic came from AI referrers?".

**Polished dashboard.** Pirsch's dashboard is clean, fast, German-engineered. If you want a dashboard, Pirsch's is good. We don't have one.

**Same-country hosting.** Pirsch is hosted in Germany (Hannover). We're hosted in Germany (Falkenstein). Both are German GmbH companies. From a GDPR posture perspective, this isn't a differentiator. But if "100% German company, German data, German support" matters to you, both check the box.

**Mature product.** Pirsch has been live since 2021, has paying customers, has shipped through GDPR shifts. We're newer.

## Where we win

**Free tier with no card.** Pirsch is trial-only (30 days, then paid). We have 100k hits/month free forever, unlimited sites, all 23 MCP tools. For new projects where you don't know if they'll succeed, that free runway matters.

**100x volume headroom at €19.** At ~$19/month equivalent, you get 10,000,000 hits with us and ~100k pageviews with Pirsch's Plus tier. Different orders of magnitude. If you have any chance of a Hacker News spike, a newsletter sendout, or a viral tweet, you'll hit Pirsch's cap on a single day.

**MCP-native interface.** The product's reason for existing. Your stats live in your existing Claude / ChatGPT / Cursor session.

```
You: "Last week's pageviews vs the previous week. What's the
     biggest change?"
Claude: "Pageviews 42,180 vs 31,420, up 34%. The big jump is on
        /pricing (8.2k vs 3.1k). Top new referrer is reddit, post
        thread on /r/selfhosted from Friday."
```

**Bot crawler visibility.** Pirsch tracks AI-referrer (human-from-AI). We additionally classify AI crawlers themselves (GPTBot, ClaudeBot, PerplexityBot, ByteSpider, etc.). You see how often your site is being indexed by AI training/answer systems. Pirsch filters those out silently.

**Server-side events.** Our ingest endpoint accepts `POST /event` directly for webhook/cron/server-side conversion tracking. First-party Ruby gem and npm wrappers are on the Pro roadmap. Pirsch is JS-only.

**Truly unlimited sites on all tiers**, including free. Pirsch caps Standard at 50 sites. Generous, but a cap.

## When you should pick Pirsch

- Your traffic is small and stable (<10k/month) and you'd rather pay $6 than worry about free-tier limits.
- You want a clean dashboard, and the built-in AI-referrer channel speaks to your use case.
- You don't use Claude/ChatGPT/Cursor as a daily workflow.

## When you should pick us

- You spend hours daily in Claude or ChatGPT and want analytics inside that flow.
- Your free runway matters. No card, no time limit.
- You may spike. 100x more hits at the same price point as Pirsch's Plus.
- You want explicit AI-crawler visibility, not silent filtering.
- You need server-side event tracking.

## What's not a real difference

- Both EU-hosted, both German companies.
- Both cookieless by default in strict mode.
- Both targeting the privacy-first market.

## Migration

Run both in parallel for a month. Add our tracking snippet alongside Pirsch's (no conflict). Ask the same questions in both. Pick whichever workflow fits better for your situation.

Some teams keep Pirsch on their public marketing site (the dashboard is useful for non-technical contributors) and add us on internal tools and side projects (where the chat workflow is faster).

## Try it

[Sign up free](/), 100k hits/month, no card.

Specific Pirsch feature you can't live without? [Email us](mailto:hello@mcp-analytics.com).

