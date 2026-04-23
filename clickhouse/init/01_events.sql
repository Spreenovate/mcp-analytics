CREATE DATABASE IF NOT EXISTS mcpa;

CREATE TABLE IF NOT EXISTS mcpa.events
(
    site_id          String,
    timestamp        DateTime64(3, 'UTC'),
    event_name       LowCardinality(String),
    session_id       UInt64,
    visitor_id       UInt64,
    url_path         String,
    url_host         LowCardinality(String),
    referrer_host    LowCardinality(String),
    referrer_path    String,
    utm_source       LowCardinality(String),
    utm_medium       LowCardinality(String),
    utm_campaign     LowCardinality(String),
    browser          LowCardinality(String),
    browser_version  LowCardinality(String),
    os               LowCardinality(String),
    device_type      LowCardinality(String),
    country          LowCardinality(String),
    region           LowCardinality(String),
    city             LowCardinality(String),
    prop_keys        Array(String),
    prop_values      Array(String),
    ingested_at      DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(timestamp)
ORDER BY (site_id, timestamp, event_name)
TTL toDateTime(timestamp) + INTERVAL 2 YEAR
SETTINGS index_granularity = 8192;
