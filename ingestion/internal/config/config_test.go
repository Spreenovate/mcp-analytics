package config

import (
	"testing"
	"time"
)

func TestFromEnv_DefaultsWhenUnset(t *testing.T) {
	for _, k := range []string{
		"INGEST_LISTEN", "DATABASE_PATH", "CLICKHOUSE_URL", "CLICKHOUSE_USER",
		"CLICKHOUSE_PASSWORD", "CLICKHOUSE_DB", "BATCH_MAX_EVENTS",
		"BATCH_INTERVAL", "USAGE_FLUSH_INTERVAL", "SITE_CACHE_REFRESH",
		"RATE_EVENTS_PER_SECOND", "STATIC_DIR",
	} {
		t.Setenv(k, "")
	}

	c := FromEnv()
	if c.ListenAddr != ":8081" {
		t.Errorf("ListenAddr default: got %q", c.ListenAddr)
	}
	if c.ClickHouseDB != "mcpa" {
		t.Errorf("ClickHouseDB default: got %q", c.ClickHouseDB)
	}
	if c.BatchMaxEvents != 1000 {
		t.Errorf("BatchMaxEvents default: got %d", c.BatchMaxEvents)
	}
	if c.BatchInterval != 5*time.Second {
		t.Errorf("BatchInterval default: got %v", c.BatchInterval)
	}
	if c.EventsPerSecondPerSite != 100 {
		t.Errorf("EventsPerSecondPerSite default: got %d", c.EventsPerSecondPerSite)
	}
}

func TestFromEnv_OverridesFromEnv(t *testing.T) {
	t.Setenv("INGEST_LISTEN", ":9000")
	t.Setenv("CLICKHOUSE_URL", "http://ch:9001")
	t.Setenv("BATCH_MAX_EVENTS", "42")
	t.Setenv("BATCH_INTERVAL", "250ms")
	t.Setenv("RATE_EVENTS_PER_SECOND", "7")

	c := FromEnv()
	if c.ListenAddr != ":9000" {
		t.Errorf("ListenAddr: got %q", c.ListenAddr)
	}
	if c.ClickHouseURL != "http://ch:9001" {
		t.Errorf("ClickHouseURL: got %q", c.ClickHouseURL)
	}
	if c.BatchMaxEvents != 42 {
		t.Errorf("BatchMaxEvents: got %d", c.BatchMaxEvents)
	}
	if c.BatchInterval != 250*time.Millisecond {
		t.Errorf("BatchInterval: got %v", c.BatchInterval)
	}
	if c.EventsPerSecondPerSite != 7 {
		t.Errorf("EventsPerSecondPerSite: got %d", c.EventsPerSecondPerSite)
	}
}

func TestFromEnv_InvalidValuesFallBackToDefault(t *testing.T) {
	t.Setenv("BATCH_MAX_EVENTS", "not-a-number")
	t.Setenv("BATCH_INTERVAL", "not-a-duration")

	c := FromEnv()
	if c.BatchMaxEvents != 1000 {
		t.Errorf("invalid int should fall back, got %d", c.BatchMaxEvents)
	}
	if c.BatchInterval != 5*time.Second {
		t.Errorf("invalid duration should fall back, got %v", c.BatchInterval)
	}
}
