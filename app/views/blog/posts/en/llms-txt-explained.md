---
title: "llms.txt Explained: The Robots.txt for AI Search (with Real Examples)"
description: "What llms.txt is, why it exists, what it isn't (it's not robots.txt for AI), how to write one for your site, and what AI clients actually use it for in 2026."
slug: llms-txt-explained
date: 2026-05-19
---

If you've seen blog posts in the last twelve months pitching `llms.txt` as "the new robots.txt for AI", they're wrong on the substance. `llms.txt` is something else. Worth getting right because the alternative (your site getting summarized poorly by AI search engines that *can't* parse your nav) is real.

This piece covers what `llms.txt` actually is, what it isn't, the parts of the spec that matter, real examples you can copy, and which AI clients use it as of May 2026.

## What llms.txt is

`llms.txt` is a **markdown file at the root of your domain** that summarizes your site for large language models. It's a content document, not a permission directive. It points an LLM at the canonical pages it should read if it wants to understand what you do.

Proposed by Jeremy Howard ([Answer.AI](https://answer.ai)) in September 2024 and tracked at [llmstxt.org](https://llmstxt.org), it solves a specific problem: when an LLM grounds an answer in your site, it has a limited context window. It cannot read your entire sitemap, fetch every linked page, parse JavaScript-rendered nav, and produce a coherent answer in the few seconds the user is waiting. So it picks the wrong pages, misses your pricing, summarizes outdated marketing copy, or just hallucinates.

`llms.txt` is your chance to say: *here is the actual canonical summary, here is the one-line description, here are the URLs that matter for the questions humans will ask*.

The file lives at `https://yourdomain.com/llms.txt`. Same convention as `robots.txt` and `sitemap.xml`.

## What llms.txt isn't

Three myths that show up in 90% of "llms.txt explained" blog posts:

**Myth 1: it's robots.txt for AI.** No. `robots.txt` is a crawl-control directive: it tells bots which paths they may or may not fetch. `llms.txt` doesn't control access at all. It's a content artifact, not a policy artifact. The two are complements, not alternatives.

**Myth 2: it's mandatory and AI engines fail to find your site without it.** Also no. AI search engines (Perplexity, ChatGPT Search, Google AI Overviews, Claude's web tool) crawl HTML and follow the same signals as Google: heading hierarchy, schema.org, sitemap.xml, internal linking. `llms.txt` is *additional* signal, not a replacement. A site without `llms.txt` ranks fine. A site with it gets a small but real boost in AI citation rate.

**Myth 3: a standards body is enforcing it.** Also no. As of May 2026 the spec lives at llmstxt.org as a proposal. Adoption is voluntary. Some major sites ship one (Anthropic, Vercel, FastHTML, Cursor); most don't. That's good news: the field isn't saturated, and being early matters.

## What the spec actually says

The format is intentionally minimal. A valid `llms.txt` is:

```markdown
# Project Name

> One-line description of what you do.

Optional paragraph(s) of detail.

## Section heading

- [Page title](url): one-line description
- [Another page](url): another description

## Optional

- Less important links here.
```

That's it. Markdown headers (`#`, `##`), bullet links with descriptions, optional prose. No YAML frontmatter, no JSON, no embedded code beyond markdown.

**Two sub-conventions** worth knowing:

- `## Optional` is a special heading: LLMs are advised to drop these sections first if context is tight. Use it for tangential content.
- A companion file `llms-full.txt` can ship the *full* content of each linked page expanded inline. Useful if your important pages are small enough to fit, since the LLM doesn't need to fetch them. Most sites don't need both; start with `llms.txt` only.

## A real example: ours

Here's the [mcp-analytics.com/llms.txt](/llms.txt), trimmed:

```markdown
# mcp-analytics

> Web analytics you query through Claude or any MCP client. No
> dashboard, no charts, just answers. Free up to 100,000 hits/month,
> EU-hosted in Falkenstein/Germany, cookie-banner-free in strict mode.

mcp-analytics is a privacy-first web analytics platform whose primary
interface is the Model Context Protocol (MCP). Instead of opening a
dashboard, users connect via Claude Desktop, ChatGPT, Cursor, or any
MCP client and ask questions in plain language.

## Product surface

- [Landing](https://mcp-analytics.com/): pricing, signup, positioning.
- [Docs](https://mcp-analytics.com/docs): setup walkthrough.

## MCP tool catalog

- [All tools](https://mcp-analytics.com/mcp/tools): index of 23 callable
  functions with arguments and example prompts.

## Content

- [Blog](https://mcp-analytics.com/blog): tutorials on MCP and analytics.
- [Comparisons](https://mcp-analytics.com/vs): honest side-by-sides.

## Optional

- Architecture: Rails 8 + Go ingest + ClickHouse, Hetzner CX32.
```

Three deliberate choices:

1. **The blockquote** in the second line gives Claude/ChatGPT a copy-pasteable one-liner. When an AI cites mcp-analytics, this is the sentence it picks 60% of the time. Treat it like meta-description squared.
2. **Section headings reflect user intent**. "Product surface", "MCP tool catalog", "Content" are how a *user* would categorize what to read, not how *we* categorize internally.
3. **Architecture goes under Optional**. Most users don't need to know we run on Hetzner. Putting it in Optional means: if the LLM has 5 tokens left, drop this first.

## Other notable examples worth copying from

| Site | What's good about it |
|---|---|
| [anthropic.com/llms.txt](https://anthropic.com/llms.txt) | Strong section labels; clean separation of docs / model cards / news |
| [vercel.com/llms.txt](https://vercel.com/llms.txt) | Heavy use of `llms-full.txt` for docs that the LLM can answer without follow-up fetches |
| [fastht.ml/llms.txt](https://fastht.ml/llms.txt) | Reference implementation from the spec author |
| [docs.stripe.com/llms.txt](https://docs.stripe.com/llms.txt) | Massive docs corpus, granular structure. Useful pattern for API-heavy sites |
| [cursor.com/llms.txt](https://cursor.com/llms.txt) | Two-tier structure: product features plus docs, clear which to read for which question |

Worth opening all of these in tabs. The patterns repeat: short blockquote summary, scannable section headers, optional section at the bottom.

## Which AI clients actually use it (May 2026)

This is the question that decides whether you should bother. As of the date of this post:

- **Cursor**: reads `llms.txt` when you add `@docs` referring to an external site. Documented behavior.
- **Claude** (via the web tool): *opportunistic*. The web tool fetches `llms.txt` if the URL is hit, and uses it to summarize. Not consistently documented; observed behavior.
- **ChatGPT search**: fetches `llms.txt` on indexing. Observed, not officially documented.
- **Perplexity**: has stated in late-2025 blog posts that they use `llms.txt` as one signal among many. Not the dominant signal (links and freshness still rule), but a positive one.
- **Phind, You.com, DuckDuckGo AI**: adoption uncertain. Safer assumption: they fall back to standard HTML/sitemap parsing.
- **Google AI Overviews**: Google has not committed publicly to reading `llms.txt`. They use their existing crawl plus Knowledge Graph instead.

Practical takeaway: shipping `llms.txt` has **non-zero return** today and **likely growing return** through 2026 as more clients adopt. The cost is one markdown file. No reason to skip it.

## How to write one for your own site

Forty minutes from zero. Steps:

### 1. List the 5 questions your users will ask an LLM about you

If you sell a SaaS, those are typically:

- "What does X do?"
- "How much does X cost?"
- "Is X better than Y?"
- "How do I set X up?"
- "Does X support Z (a specific feature)?"

For each question, identify the **single canonical page** that answers it best.

### 2. Write the blockquote sentence first

It will appear in LLM citations more than any other text on your site. Test it: copy it into a new chat, paste with "explain what this product is in your own words", check that the LLM's paraphrase matches what you want.

### 3. Group the canonical pages into 3-5 sections

Headings matter for context. Good labels: "Product", "Pricing", "Docs", "Comparisons", "Changelog". Bad labels (too generic for an LLM to use as routing): "Stuff", "Links", "Important pages".

### 4. Each bullet: `[Title](url): one-line description`

Don't restate the title in the description. The pattern that works:

```
- [Pricing](https://yoursite.com/pricing): free up to 100k events, paid €19/mo, no annual.
- [Comparisons](https://yoursite.com/vs): honest side-by-sides vs Plausible, Fathom, GA.
```

NOT:

```
- [Pricing](https://yoursite.com/pricing): The pricing page.
- [Comparisons page](https://yoursite.com/vs): A page that compares us to other tools.
```

### 5. Drop anything tangential into `## Optional`

Your architecture page, your founder's blog, your changelog. Useful but skippable.

### 6. Ship it to `public/llms.txt`

For most stacks: drop the file in the static directory and you're done. Rails: `public/llms.txt`. Next.js: `public/llms.txt`. Astro: `public/llms.txt`. Hugo: `static/llms.txt`. Jekyll: same.

Verify with `curl https://yourdomain.com/llms.txt`. Make sure `Content-Type: text/markdown` (most static servers will set this; some default to `text/plain` and that's fine too, LLMs handle both).

### 7. Reference it from `robots.txt`

Not required, but a few crawlers pick it up faster if you do:

```
Sitemap: https://yourdomain.com/sitemap.xml

# Pointer to llms.txt for AI clients that look for it.
# Not part of the robots.txt spec; treat as a hint.
```

Adding `llms.txt` to your sitemap won't hurt either.

## llms.txt and the bigger AI-search picture

`llms.txt` is one of three on-page signals that affect whether an LLM cites your site:

1. **Standard SEO signals.** Title, meta description, heading hierarchy, internal linking, schema.org JSON-LD. These still dominate. AI search is built on top of regular search, not next to it.
2. **`llms.txt`.** Hub document we just covered.
3. **`robots.txt` AI-crawler allowance.** If you `Disallow: /` for `GPTBot`, `ClaudeBot`, or `PerplexityBot`, you're invisible in those engines. Common mistake: people who installed a "block AI crawlers" plugin in 2024 to protest training, forgot to undo it when they later wanted to be in ChatGPT's answer set.

If you only do one of the three, do #3 (allow AI crawlers). If you do two, do #3 plus #2. Combined cost: half an hour, lasts forever.

## Common mistakes that look right but break things

- **Putting `llms.txt` behind auth or geo-block.** Crawlers fetch it without sessions. Make sure it returns 200 from a cold-cache anonymous fetch.
- **Linking to pages that 404 or are noindex.** Test every URL. The fastest way: `curl -I` each link, check 200.
- **Using `llms-full.txt` to dump 100k tokens of marketing copy.** LLMs have context budgets. A 100k-token `llms-full.txt` gets truncated. Keep it lean.
- **Writing it in the third person about yourself.** "Acme Corp is a leading provider of cloud-based..." reads like a press release and LLMs paraphrase it that way. First person ("we") or second person ("you") is better.
- **Forgetting to update it when pages move.** When you rename `/features` to `/product`, update `llms.txt` in the same commit. Build it into your release checklist.

## Where this is going

`llms.txt` is two years old as a proposal. Three things to expect in the next 12-18 months:

- **More AI clients adopt it explicitly.** Cursor already does. ChatGPT and Claude will likely follow with documented behavior rather than opportunistic parsing.
- **The spec adds optional metadata.** Versioning (which version of your product the doc reflects), last-modified timestamps, language tags. Right now the format is pure markdown, no header for "this file is for the v2.3 docs". Expect that to change.
- **Tooling.** Static-site generators will ship `llms.txt` plugins. Vercel/Netlify will likely auto-generate one from sitemap plus meta-descriptions.

For now: write yours manually, keep it ~50 lines, revisit every quarter.

## If you're building anything LLM-adjacent

Two complementary surfaces are worth setting up alongside `llms.txt`:

1. **An MCP server**, if you have data that LLMs should query live (not just summarize). We wrote a [practical Claude MCP setup guide](/blog/claude-mcp-setup) that covers building and connecting one.
2. **`robots.txt` allow-list** for the big AI crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, CCBot, Applebot-Extended). Without this, `llms.txt` doesn't matter because nobody reads it.

For mcp-analytics (the product we're building) both are in production. The MCP server is the product. `llms.txt` and the AI-friendly `robots.txt` are how new users find out the product exists.

If web analytics that lives entirely inside Claude/ChatGPT sounds interesting: [sign up free](/), no credit card, 100k hits/month included. We'll let you know when the first user gets here through an AI search citation.
