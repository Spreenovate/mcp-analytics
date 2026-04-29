-- Stufe-2 client-side signals: timezone, language, color-scheme preference,
-- viewport size, engagement time, scroll depth.
--
-- All values come from the tracker (privacy-clean Web APIs), never from
-- IP-based lookups. Aggregable, not personally-identifiable.
--
-- engagement_seconds + scroll_depth are populated only on rows where
-- event_name = 'engagement', which the tracker fires once per page lifetime
-- via sendBeacon on pagehide/visibilitychange:hidden. Pageview rows leave
-- both at 0.
--
-- Safe to re-run; uses ADD COLUMN IF NOT EXISTS. For an existing prod CH:
--
--   kamal accessory exec clickhouse \
--     "clickhouse-client --query \"$(cat clickhouse/init/05_engagement_signals.sql)\""

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS timezone           LowCardinality(String) DEFAULT '',
  ADD COLUMN IF NOT EXISTS language           LowCardinality(String) DEFAULT '',
  ADD COLUMN IF NOT EXISTS color_scheme       LowCardinality(String) DEFAULT '',
  ADD COLUMN IF NOT EXISTS viewport_w         UInt16                 DEFAULT 0,
  ADD COLUMN IF NOT EXISTS viewport_h         UInt16                 DEFAULT 0,
  ADD COLUMN IF NOT EXISTS engagement_seconds UInt32                 DEFAULT 0,
  ADD COLUMN IF NOT EXISTS scroll_depth       UInt8                  DEFAULT 0;
