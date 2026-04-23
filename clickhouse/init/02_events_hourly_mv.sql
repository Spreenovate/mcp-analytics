CREATE MATERIALIZED VIEW IF NOT EXISTS mcpa.events_hourly
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (site_id, hour, event_name, url_path)
AS SELECT
    site_id,
    toStartOfHour(timestamp) AS hour,
    event_name,
    url_path,
    count() AS events,
    uniqState(session_id) AS sessions_state,
    uniqState(visitor_id) AS visitors_state
FROM mcpa.events
GROUP BY site_id, hour, event_name, url_path;
