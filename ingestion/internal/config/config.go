package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr string

	SQLitePath string

	ClickHouseURL      string
	ClickHouseUser     string
	ClickHousePassword string
	ClickHouseDB       string

	BatchMaxEvents int
	BatchInterval  time.Duration

	UsageFlushInterval time.Duration
	SiteCacheRefresh   time.Duration

	EventsPerSecondPerSite int

	StaticDir string
}

func FromEnv() Config {
	return Config{
		ListenAddr:             envStr("INGEST_LISTEN", ":8081"),
		SQLitePath:             envStr("DATABASE_PATH", "/rails/storage/production.sqlite3"),
		ClickHouseURL:          envStr("CLICKHOUSE_URL", "http://clickhouse:8123"),
		ClickHouseUser:         envStr("CLICKHOUSE_USER", "default"),
		ClickHousePassword:     envStr("CLICKHOUSE_PASSWORD", ""),
		ClickHouseDB:           envStr("CLICKHOUSE_DB", "mcpa"),
		BatchMaxEvents:         envInt("BATCH_MAX_EVENTS", 1000),
		BatchInterval:          envDur("BATCH_INTERVAL", 5*time.Second),
		UsageFlushInterval:     envDur("USAGE_FLUSH_INTERVAL", 30*time.Second),
		SiteCacheRefresh:       envDur("SITE_CACHE_REFRESH", 30*time.Second),
		EventsPerSecondPerSite: envInt("RATE_EVENTS_PER_SECOND", 100),
		StaticDir:              envStr("STATIC_DIR", "./static"),
	}
}

func envStr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func envDur(key string, fallback time.Duration) time.Duration {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
