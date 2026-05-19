---
competitor: "Umami"
competitor_url: "https://umami.is"
slug: umami
title: "mcp-analytics vs Umami (2026)"
description: "Umami is the open-source darling with the most generous free tier. We're MCP-native and proprietary. Where each wins."
date: 2026-05-19
verdict_us: "MCP-native. Your stats live in Claude/ChatGPT/Cursor, not in a tab. Proprietary, EU-hosted, 100k free hits/mo, bot/AI-crawler taxonomy."
verdict_them: "Open-source, MIT-licensed, self-hostable. Cloud free tier is 1M events. The pragmatic choice if open-source matters to you ideologically or operationally."
table:
  - feature: "License"
    us: "Proprietary."
    them: "MIT (self-hostable, fork-able)."
  - feature: "Cloud free tier"
    us: "100k hits/mo, unlimited sites, no card."
    them: "1M events/mo, 3 sites."
  - feature: "Cloud paid entry"
    us: "€19/mo for 10M hits, unlimited sites."
    them: "~$20/mo Pro for 100k events first paid tier (then volume tiers)."
  - feature: "Self-hostable"
    us: "No (Enterprise tier offers dedicated host)."
    them: "Yes, main distribution path."
  - feature: "Dashboard UI"
    us: "None. MCP-only."
    them: "Web dashboard, clean and minimal."
  - feature: "MCP server"
    us: "Yes, primary interface. 23 tools."
    them: "No."
  - feature: "EU hosting"
    us: "Hetzner Falkenstein (Germany)."
    them: "Cloud is on AWS (US default; EU available); self-host wherever."
  - feature: "Cookieless"
    us: "Yes (strict mode)."
    them: "Yes by default."
  - feature: "Custom events"
    us: "JS + server-side SDK on Pro."
    them: "JS-based; can call API directly."
  - feature: "AI / bot taxonomy"
    us: "8 traffic classes including ai_user_action, ai_crawler."
    them: "Filters bots; no breakdown."
  - feature: "Data retention"
    us: "1 year (Free) / 3 years (Pro) / custom (Enterprise)."
    them: "Unlimited on paid; depends on storage on self-host."
---

Umami is the open-source darling of privacy-first analytics. MIT-licensed, self-hostable, generous free Cloud tier. They've built a community-loved product. The honest comparison:

## Where Umami wins

**Open source, MIT-licensed.** The single biggest reason to pick Umami over anyone else. You can self-host it for free, fork it, contribute to it, audit the code. We're proprietary. No version of us runs on your own infrastructure (except our Enterprise tier, which is single-tenant on Hetzner. Not the same thing as self-hostable code).

**The biggest cloud free tier.** Umami Cloud free is 1M events/month with 3 sites. Ours is 100k hits/month with unlimited sites. Different shape: they prioritize hits-volume, we prioritize site-count. If you run a single big site, Umami Cloud's free is more generous. If you run a portfolio of small sites, ours is.

**Self-hostable as the primary distribution path.** Umami's main story is self-host. You install it on your VPS, point your tracker at it, you control everything. If your operational philosophy is "I run my own stack", Umami is the right answer.

**Community.** Big GitHub presence, many integrations, many contributors. We're a single-founder shop.

## Where we win

**MCP-native primary interface.** The entire reason we exist. Your analytics live in your existing Claude / ChatGPT / Cursor session, not in a browser tab. You ask in plain English, you get a sentence back.

```
You: "Top pages last 7 days on mysite.com."
Claude: "1. /pricing  - 4,212 views
        2. /blog/llms-txt-explained - 2,847 views
        3. / - 1,963 views
        4. /docs - 1,210 views
        5. /vs/plausible - 891 views"
```

Umami has an API, but no chat interface. To get the same answer, you open the dashboard or write code.

**Unlimited sites on free.** Umami Cloud's free is capped at 3 sites. Ours has no site cap on any tier. If you're an indie running a portfolio (main site plus half-finished side projects plus client sites), our free can absorb all of them.

**Bot and AI crawler visibility.** We classify traffic into eight buckets including `ai_user_action`, `ai_crawler`, `verified_search_bot`. Umami filters bots silently. By design they show you "real visitors only". For a privacy-first analytics target audience that's fine, but if you specifically want to know who's crawling you (GPTBot, ClaudeBot, PerplexityBot), we surface it.

**Server-side SDK** (Pro). Ruby gem, npm package, pixel endpoint. Umami requires you to call the events API directly from your backend, which works but is more setup.

**EU hosting by default.** Umami Cloud is on AWS. You can pick the EU region, but the default is US. We're on Hetzner Falkenstein, always.

**Deploy-regression tracking on the Pro roadmap.** A GitHub Action plus MCP tools to flag traffic anomalies caused by a deploy. Umami has no equivalent.

## When you should pick Umami

- Open source matters to you ideologically.
- You want to self-host (no recurring SaaS bill, you control everything).
- You have a single high-volume site and want to use the generous 1M-event cloud free tier.
- You're comfortable with self-host operations (DB backups, version upgrades, etc.).

## When you should pick us

- You spend hours daily in Claude or ChatGPT and want analytics inside that flow.
- You run multiple sites and want them all under one account.
- You want bot/AI-crawler breakdown, not silent filtering.
- You want server-side event tracking from your backend (webhooks, cron, server-side conversions).
- You want a managed service with no self-host operational burden.

## What's not a real difference

- Both are privacy-first and cookieless.
- Both have decent free tiers (different shapes).
- Both serve the indie / SaaS / dev-tools market.

## A note on the "should I self-host" question

The pragmatic answer: self-hosting Umami is a real ongoing cost. You need:

- A VPS (Hetzner CX22 minimum, ~€5/month)
- A managed Postgres or self-managed (more time, more risk)
- A backup strategy
- Version upgrades whenever a Umami release ships
- DNS, SSL, monitoring

For a small site, the answer is often "Umami Cloud free tier is enough". For a big site, you may actually be paying *more* in time-spent than our Pro tier (€19/month) would cost. We're managed. Umami Cloud is managed too. Self-host is its own choice.

## Migration

Both can run in parallel. Add our snippet alongside your Umami install (no conflict) and ask the same questions in both for a month. If you decide to move fully, dropping the Umami snippet is one line of HTML.

## Try it

[Sign up free](/), 100k hits/month, unlimited sites, no card.

If you're a self-hoster and want to evaluate without changing anything: add our snippet alongside Umami on one project, see if the chat workflow earns its keep.
