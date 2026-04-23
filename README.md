# mcp-analytics

Web analytics you drive through MCP — no dashboard, no tabs. This repo contains
the full MVP stack.

**Status:** Week-1 scaffold from the project briefing. Ingestion, ClickHouse
schema, MCP server (all tools), tracking script, Kamal deploy config. See
roadmap at the bottom.

## Architecture

Three containers on a single host (Hetzner CX32, Falkenstein):

```
                     ┌──────────────┐
  mcp-analytics.com ─┤ kamal-proxy  │──┐
                     │ (Let's Enc.) │  │
                     └──────────────┘  │
                                       ├──► Rails 8 app (web + MCP server + UI)
                                       │     • SQLite (account/site data, Solid Queue/Cache)
                                       │     • POST /mcp  (JSON-RPC 2.0)
                                       │     • /, /verify/:token, /settings, /login
                                       │
  t.mcp-analytics.com ─► kamal-proxy ──┴──► Go ingest service
                                              • POST /event   (async ClickHouse insert)
                                              • GET  /script.js
                                              • bot-filter, rate-limit, salt-hashed session ids
                                              │
                                              ▼
                                        ClickHouse 24.3
                                        • /var/lib/clickhouse
                                        • events + 2 materialized views
                                        • 2-year TTL
```

- **Rails** and **Go ingest** both read the same SQLite file (shared Docker volume,
  WAL mode). Rails owns `users`, `sites`, `email_verifications`, `magic_links`.
  Go owns writes to `usage_counters` and `unknown_site_hits` (buffered + flushed
  every 30 s).
- **ClickHouse** is accessed over HTTP from both Rails (for MCP queries) and Go
  (for async inserts). Not exposed publicly.
- **Tracking script** (`ingestion/static/script.js`, ~130 lines) is served from
  the Go container at `https://t.mcp-analytics.com/script.js`.

## Repo layout

```
app/
  controllers/                  Rails controllers (MCP, pages, verifications, sessions, settings)
  services/
    mcp/                        MCP server — JSON-RPC dispatch + tools + schemas + started guide
    analytics/                  Period parser, ClickHouse query builder
  jobs/                         Solid Queue jobs (salt rotation, purge, usage alert)
  mailers/                      Verification + magic link + operator alert
  models/                       User, Site, EmailVerification, MagicLink, UsageCounter, UnknownSiteHit
lib/click_house.rb              Thin HTTP client for ClickHouse (Rails side)
clickhouse/init/                Schema SQL (events + 2 materialized views) mounted into ClickHouse container
ingestion/                      Go ingest service (separate Docker image)
  cmd/ingest/main.go
  internal/
    bot/                        User-agent bot filter
    ch/                         ClickHouse HTTP + batcher
    config/                     Env-based config
    ratelimit/                  Per-site token bucket
    server/                     HTTP handlers (/event, /script.js, /healthz)
    session/                    Salt-based session/visitor id hashing
    sites/                      In-memory site cache (refreshed from SQLite)
    ua/                         Minimal UA sniff
    usage/                      Buffered UPSERT into usage_counters / unknown_site_hits
  static/script.js              Tracking script served by Go
config/deploy.yml               Kamal 2 deploy config
ops/backup.sh                   Daily host-level backup script
```

## Getting started (development)

```sh
bin/setup              # bundle install + db:prepare
bin/dev                # Rails on :3000 (or bin/rails s)

# In another shell: build & run the Go ingest service against a local ClickHouse
cd ingestion
docker run -d --name clickhouse -p 8123:8123 \
  -v $PWD/../clickhouse/init:/docker-entrypoint-initdb.d \
  clickhouse/clickhouse-server:24.3
DATABASE_PATH=../storage/development.sqlite3 \
  CLICKHOUSE_URL=http://localhost:8123 \
  go run ./cmd/ingest
```

Smoke-test the MCP endpoint:

```sh
curl -s http://localhost:3000/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq
```

## MCP authentication

Open question per the briefing: OAuth 2.0 vs bearer vs URL-param for remote MCP.
The MVP supports both `Authorization: Bearer <token>` header and `?token=<...>`
query param on `POST /mcp`, so users can pick whichever their client supports.
Revisit once the current Anthropic recommendation for remote MCP in 2026 is
pinned down.

Without a token: only `register_account` and `get_started_guide` are exposed.
With a valid token: all analytics tools plus `list_sites`, `add_site`,
`get_tracking_snippet`, `remove_site`, `get_account`, `regenerate_api_token`.

Rate-limit: 60 calls/minute per token (via `Rails.cache`, backed by Solid Cache).

## Privacy modes

Chosen once per site at `add_site`, non-mutable:

| mode    | session id                                                   | visitor id                                        | referrer | cookie |
|---------|--------------------------------------------------------------|---------------------------------------------------|----------|--------|
| strict  | H(daily_salt \| site_salt \| ip \| ua \| site_id)            | 0                                                 | host     | no     |
| default | H(site_salt \| ip \| ua \| site_id \| "session") (365 d)     | H(site_salt \| ip \| ua \| site_id \| "visitor")  | full     | no     |
| all     | (server-side same as default)                                | cookie-backed (tracker side)                      | full     | yes    |

Daily salt is an in-memory random per Go process, rotated every UTC midnight.
`site_salt` is per-site random (rotated every 365 days via a Solid Queue job).

## Deploy

Kamal 2 config in `config/deploy.yml`. Three pieces:

1. **Rails image** — the default repo Dockerfile, built by `kamal deploy`.
2. **Ingest image** — built separately before deploy:

   ```sh
   docker buildx build --platform linux/amd64 -t ghcr.io/mcpanalytics/ingest:latest \
     ./ingestion --push
   ```

3. **ClickHouse** — accessory using the official image with init SQL mounted.

First-time setup:

```sh
export KAMAL_REGISTRY_PASSWORD=... RAILS_MASTER_KEY=... \
       SMTP_USERNAME=... SMTP_PASSWORD=... CLICKHOUSE_PASSWORD=...
kamal setup           # provisions kamal-proxy, pulls images, first deploy
```

Replace the placeholder IP `1.2.3.4` in `config/deploy.yml` with the actual
server. DNS: `mcp-analytics.com` and `t.mcp-analytics.com` both A-records to
the server.

Backups: install `ops/backup.sh` as a host cron (example inside the script).

## Rate-limits & anti-abuse

| area                        | limit                                     |
|-----------------------------|-------------------------------------------|
| `register_account` (unauth) | 3 / IP / hour, 10 / IP / day, 5 / email-domain / day |
| `add_site` (auth)           | 10 / user / day                            |
| `magic_link`                | 20 / IP / hour                             |
| MCP queries (auth)          | 60 / minute / token                        |
| POST /event per site        | 100 req/s token-bucket (Go-side)           |
| Hit limit (free tier)       | 100 000 hits/month/account (soft cap)      |

Garbage site-id tracking (`unknown_site_hits`) is bumped by Go on every POST
/event for an unknown `data-site`; a separate alert job is TBD.

## Explicitly not in MVP

Stripe, `query_sql`, web signup form, analytics UI, realtime, goals/funnels,
A/B testing, MaxMind geo lookup (columns present but empty), team accounts,
HTTP API beyond MCP, custom tracking domains, npm package.

## Roadmap

- Phase 2: MaxMind geo, Stripe pricing tiers.
- Phase 3: Enterprise tier (dedicated server, `query_sql`, SLA).
- Phase 4: Team accounts, self-hosted tracker, connector-directory listing.

## License

Proprietary — TBD.
