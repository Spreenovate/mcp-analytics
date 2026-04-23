# mcp-analytics Getting Started

Welcome. mcp-analytics is a web-analytics service you drive through MCP — no dashboard, no tabs. This guide walks through the end-to-end setup.

## 1. Signup (via MCP, no web form)

Call `register_account` with the user's email. The response contains:

- `pending_user_id` — a handle we can reference before verification.
- `placeholder_site_id` — a string you can drop into the tracking snippet *right now*, while the user heads to their inbox.
- `message` — short human-readable status.

We email the user a verification link that opens `/verify/<token>`. That page shows their API token and the new MCP URL (with token). The user updates their MCP connector URL and returns to chat.

## 2. Pre-verify tracking

You can install the tracking snippet immediately, using the placeholder:

```html
<script defer
        data-site="DUMMY_SITE_ID_REPLACE_AFTER_VERIFY"
        src="https://t.mcp-analytics.com/script.js"></script>
```

Events that arrive for an unknown `data-site` are silently ignored server-side (the endpoint returns 204). This keeps your deploy green while the user is still verifying.

## 3. Post-verify: add a site

Once the user has updated the MCP URL with their token, call `add_site` with their domain and a privacy mode (default `strict` — EU-safe, no cookies, daily salt rotation).

The response contains the real `site_id`. Ask the user to search-replace `DUMMY_SITE_ID_REPLACE_AFTER_VERIFY` with that `site_id` in their codebase and redeploy.

## 4. Query analytics

All authenticated tools are scoped to the current user's sites. Pick one by `site_id` and ask. Common tools:

- `get_overview(site_id, period)` — pageviews, visitors, sessions, bounce rate.
- `get_timeseries(site_id, metric, period, granularity)` — charts.
- `top_pages` / `top_referrers` / `top_sources` / `breakdown`.
- `list_events` + `event_details` for custom events.
- `compare_periods` for growth checks.

Period strings: `today`, `yesterday`, `last_7_days`, `last_30_days`, `last_90_days`, `last_12_months`, or an explicit `YYYY-MM-DD..YYYY-MM-DD`.

## 5. Custom events

Fire anything from the tracker with:

```js
window.mcpa('track', 'signup', { plan: 'pro' });
```

Properties are limited to 20 keys and 10kb per event, primitives only (string/number/bool). Keep them non-PII — the backend doesn't filter them.

## 6. Privacy modes

Chosen once when the site is added; not changeable afterwards.

- **strict** — daily salt, no visitor_id, no cookies, no GDPR banner needed. Default.
- **default** — site-salt-based visitor tracking (~1 year), still cookie-free.
- **all** — persistent cookie, cross-subdomain, full retention. Site owner handles GDPR.

## 7. Limits

Free tier: 100,000 hits/month per account across all sites. Over that, events keep ingesting but MCP responses include a usage warning.
