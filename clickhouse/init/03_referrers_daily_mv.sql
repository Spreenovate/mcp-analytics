CREATE MATERIALIZED VIEW IF NOT EXISTS mcpa.referrers_daily
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (site_id, day, referrer_host)
AS SELECT
    site_id,
    toDate(timestamp) AS day,
    referrer_host,
    count() AS visits,
    uniqState(session_id) AS sessions_state
FROM mcpa.events
WHERE event_name = 'pageview' AND referrer_host != ''
GROUP BY site_id, day, referrer_host;
