# mcp-analytics — Quick Reference for Connected Agents

You're authenticated. mcp-analytics is a web-analytics service the user drives entirely through their MCP client (you) — there's no dashboard. This guide is a working-context cheat sheet.

## How the user got here

The MCP server is OAuth-protected (RFC 6749 + 8707, PKCE). When the client added the connector URL, an OAuth flow ran: the user entered their email, clicked the verification link we mailed them, granted consent, and the client received an access token bound to this resource. That's the only setup ceremony. No URL pasting, no token shuffling.

## 1. Add a site

Most accounts start with zero sites. Call `add_site` with the user's domain and a privacy mode:

- **strict** (recommended default) — no cookies, daily-rotating salt, `visitor_id` is always 0. EU-safe, no banner needed.
- **balanced** — no cookies, daily-rotating hash, same-day visitor dedup.
- **all** — persistent cookie, cross-session tracking. The site owner handles GDPR.

Privacy mode **cannot be changed after creation** — historical data integrity matters.

The response contains the real `site_id`. Hold onto it for the snippet step.

## 2. Install the tracking snippet

Call `get_tracking_snippet` with the `site_id`. You get a one-line `<script>` tag. Find the right place in the user's codebase (root layout, base template) and drop it in. After deploy, the first pageview lands within seconds.

## 3. Query analytics

All read tools take `site_id` and (optionally) `period`. Period accepts `today`, `yesterday`, `last_7_days`, `last_30_days`, `last_90_days`, `last_12_months`, or an explicit `YYYY-MM-DD..YYYY-MM-DD`.

Common tools:

- `get_overview` — TL;DR for the period: pageviews, visitors, sessions, bounce rate, top page/source, bot share, top events.
- `get_timeseries` — bucketed metrics for charts.
- `top_pages` / `top_referrers` / `top_sources` / `breakdown`.
- `list_events` + `event_details` for custom events.
- `compare_periods` for growth deltas.

If the account has more than one site and the user didn't specify which, **ask before querying**. Every analytics response includes `site_id` and `domain` — echo the domain in your answer so the user can confirm.

## 4. Custom events

The tracker exposes a queue stub:

```js
window.mcpa('track', 'signup', { plan: 'pro' });
```

Properties: 20 keys max, 10kb per event, primitives only (string/number/bool). Keep them non-PII — the backend doesn't filter.

## 5. Limits

Free tier: 100,000 hits/month per account across all sites. Over that, events keep ingesting; MCP responses include a usage warning.
