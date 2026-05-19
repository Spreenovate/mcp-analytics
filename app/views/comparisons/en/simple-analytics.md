---
competitor: "Simple Analytics"
competitor_url: "https://simpleanalytics.com"
slug: simple-analytics
title: "mcp-analytics vs Simple Analytics (2026)"
description: "Simple Analytics is the no-cookie, no-events alternative. We're MCP-native with custom events. Where each wins."
date: 2026-05-19
verdict_us: "MCP-native, server-side events on Pro, AI crawler taxonomy, 100k free hits/mo no card. Best for the Claude/Cursor power user who needs more than just pageviews."
verdict_them: "The radically simple option. EU-hosted (Netherlands), no cookies, no events by default. Best for someone who only wants pageviews and referrers and nothing else."
table:
  - feature: "Price entry"
    us: "Free 100k hits/mo.\n€19/mo for 10M hits."
    them: "No free tier (14-day trial).\n$9/mo Starter (100k pageviews)."
  - feature: "Hits at ~$19"
    us: "10,000,000 / month"
    them: "Volume-priced; ~$19 = ~250k pageviews"
  - feature: "MCP server"
    us: "Yes, 23 tools, primary interface."
    them: "No."
  - feature: "Dashboard UI"
    us: "None."
    them: "Single-page minimalist dashboard. The benchmark for 'just pageviews'."
  - feature: "EU hosting"
    us: "Hetzner Falkenstein (Germany)."
    them: "Netherlands (Amsterdam)."
  - feature: "Cookieless"
    us: "Yes (strict mode)."
    them: "Yes by default; the brand is built on it."
  - feature: "Custom events"
    us: "JS + server-side SDK on Pro."
    them: "Limited (separate add-on/tier)."
  - feature: "AI / bot taxonomy"
    us: "8 traffic classes incl. ai_user_action, ai_crawler."
    them: "Bots filtered."
  - feature: "Unlimited sites"
    us: "Yes, all tiers."
    them: "Yes."
  - feature: "Data retention"
    us: "1 year (Free) / 3 years (Pro) / custom (Enterprise)."
    them: "Forever on paid."
---

Simple Analytics is the radically minimalist take on web analytics. No cookies, no events, just pageviews and referrers. They've built a small, beloved product with a Dutch team. The honest comparison:

## Where Simple Analytics wins

**The dashboard.** Simple Analytics built their brand on a single-page minimalist dashboard. If you literally only want pageviews and referrers, it's the cleanest UX you can get. We have no UI.

**Forever-retention.** Data kept forever on any paid plan. We're 1y / 3y / custom.

**Brand and maturity.** Simple Analytics has been live since 2018, has a loyal customer base, has shipped through every privacy regulation shift. They're a known quantity.

**Pure simplicity.** If "I just want pageviews, leave me alone" is your philosophy, Simple Analytics matches it. We can match it too (use only `get_overview` and `top_pages` and ignore the other 21 tools), but our existence is *because* people often want more.

## Where we win

**Free tier with no card.** Simple Analytics has a 14-day trial. We're free up to 100k hits/month, unlimited sites, no card.

**40x more volume at the same price.** ~$19/month gets you ~250k pageviews at Simple Analytics versus our 10M hits. If you have any volume above hobby-level, the math shifts dramatically.

**MCP primary interface.** You ask in chat, you get an answer. Simple Analytics has an API for programmatic access, but no chat interface.

**Custom events as a first-class concept.** Simple Analytics's events story is limited. You can track them but the workflow is constrained compared to ours. Our ingest endpoint accepts `POST /event` directly from your backend (webhooks, cron, server-side conversions); first-party Ruby/npm wrappers are on the Pro roadmap.

**AI crawler visibility.** Simple Analytics filters bots; we surface them across 8 classes.

**Deploy-regression tracking on the Pro roadmap.** GitHub Action plus MCP tools to flag traffic anomalies caused by a deploy. Simple Analytics has nothing similar.

## When you should pick Simple Analytics

- You only want pageviews and referrers. Anything more is noise to you.
- You're aesthetically committed to a single-page dashboard.
- You don't use Claude/ChatGPT as a daily workflow.

## When you should pick us

- You spend daily time in Claude/ChatGPT/Cursor.
- You need custom events from your backend (webhooks, conversions, server-side).
- You may spike or grow. 40x more hits per dollar.
- You want bot/AI-crawler breakdown.

## What's not a real difference

- Both privacy-first, cookieless, EU-hosted.
- Both target the indie/SaaS/blog market.

## Try it

[Sign up free](/), 100k hits/month, no card.
