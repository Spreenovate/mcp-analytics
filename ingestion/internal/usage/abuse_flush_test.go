package usage

import (
	"context"
	"database/sql"
	"io"
	"log/slog"
	"testing"
	"time"

	_ "modernc.org/sqlite"
)

func newFlushDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	schema := []string{
		`CREATE TABLE usage_counters (
			id INTEGER PRIMARY KEY, site_id TEXT NOT NULL, month DATE NOT NULL,
			hit_count INTEGER NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
			UNIQUE(site_id, month)
		)`,
		`CREATE TABLE unknown_site_hits (
			id INTEGER PRIMARY KEY, site_id_attempted TEXT NOT NULL, hour DATETIME NOT NULL,
			hit_count INTEGER NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
			UNIQUE(site_id_attempted, hour)
		)`,
		`CREATE TABLE abuse_events (
			id INTEGER PRIMARY KEY, ip TEXT NOT NULL, kind TEXT NOT NULL,
			unique_sites INTEGER NOT NULL, blocked_until DATETIME NOT NULL,
			notified_at DATETIME, created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL
		)`,
	}
	for _, s := range schema {
		if _, err := db.Exec(s); err != nil {
			t.Fatalf("schema: %v", err)
		}
	}
	return db
}

func TestFlush_WritesAbuseAlerts(t *testing.T) {
	db := newFlushDB(t)
	b := NewBuffer(db, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))

	at := time.Date(2026, 4, 23, 10, 0, 0, 0, time.UTC)
	b.RecordAbuse(AbuseAlert{
		IP: "1.2.3.4", UniqueSites: 150,
		BlockedUntil: at.Add(time.Hour), At: at,
	})
	b.RecordAbuse(AbuseAlert{
		IP: "5.6.7.8", UniqueSites: 200,
		BlockedUntil: at.Add(time.Hour), At: at,
	})

	b.flush(context.Background())

	if n := b.PendingAbuseAlerts(); n != 0 {
		t.Errorf("pending after flush: got %d, want 0", n)
	}

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM abuse_events`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 2 {
		t.Fatalf("abuse_events rows: got %d, want 2", count)
	}

	var ip string
	var uniq int
	var kind string
	if err := db.QueryRow(
		`SELECT ip, unique_sites, kind FROM abuse_events WHERE ip = '1.2.3.4'`,
	).Scan(&ip, &uniq, &kind); err != nil {
		t.Fatal(err)
	}
	if uniq != 150 {
		t.Errorf("unique_sites: got %d, want 150", uniq)
	}
	if kind != "garbage_site_ids" {
		t.Errorf("kind: got %q", kind)
	}
}

func TestFlush_AbuseAlertsAloneStillFlushes(t *testing.T) {
	// Regression: earlier the flush had a `if len(pending)==0 && len(unknown)==0 { return }`
	// which would skip even if abuse alerts were queued.
	db := newFlushDB(t)
	b := NewBuffer(db, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))

	b.RecordAbuse(AbuseAlert{
		IP: "only-alert", UniqueSites: 101,
		BlockedUntil: time.Now().Add(time.Hour), At: time.Now(),
	})

	b.flush(context.Background())

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM abuse_events`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("got %d rows, want 1 — flush skipped when only alerts pending", count)
	}
}
