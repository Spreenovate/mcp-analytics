-- Phase 1 of AI-bot classification.
--
-- Until now the Go ingest dropped any request whose User-Agent matched a
-- bot pattern. That threw away a useful signal — AI agents (ChatGPT, Claude,
-- Perplexity), search indexers (Googlebot), and link unfurlers (Slackbot)
-- all looked identical to spam scanners and disappeared. Now we keep
-- everything and label it; default queries hide bots, but a new MCP tool
-- exposes the breakdown.
--
-- Two new columns. Both default-safe so old-binary inserts (without the
-- new fields) keep working:
--   - traffic_class: coarse bucket. Phase 1 only emits 'user' or 'bot';
--                    Phase 2 will refine into ai_user_action / ai_search /
--                    ai_training / search_index / social_unfurl / scanner.
--   - user_agent:    raw UA so future classification can run retroactively
--                    over historical rows. (We never log IP so this stays
--                    GDPR-safe — UA alone is not personal data.)
--
-- This file uses ADD COLUMN IF NOT EXISTS so it is safe to re-run on a
-- ClickHouse instance that already has the columns. The Docker init
-- mechanism only fires on a brand-new data dir, so for an existing prod
-- ClickHouse run the same statements via:
--
--   kamal accessory exec clickhouse \
--     "clickhouse-client --query \"$(cat clickhouse/init/04_traffic_class.sql)\""

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS traffic_class LowCardinality(String) DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS user_agent    String                 DEFAULT '';
