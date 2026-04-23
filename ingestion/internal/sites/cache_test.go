package sites

import (
	"context"
	"database/sql"
	"io"
	"log/slog"
	"testing"
	"time"

	_ "modernc.org/sqlite"
)

func newDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	_, err = db.Exec(`
		CREATE TABLE sites (
			id INTEGER PRIMARY KEY,
			site_id TEXT NOT NULL,
			user_id INTEGER NOT NULL,
			domain TEXT NOT NULL,
			privacy_mode TEXT NOT NULL,
			site_salt TEXT NOT NULL,
			deleted_at DATETIME
		);
	`)
	if err != nil {
		t.Fatalf("create sites: %v", err)
	}
	return db
}

func insertSite(t *testing.T, db *sql.DB, siteID, mode string, deleted bool) {
	t.Helper()
	var deletedAt interface{}
	if deleted {
		deletedAt = time.Now().UTC().Format(time.RFC3339)
	}
	_, err := db.Exec(
		`INSERT INTO sites (site_id, user_id, domain, privacy_mode, site_salt, deleted_at)
		 VALUES (?, 1, 'example.com', ?, 'salt', ?)`,
		siteID, mode, deletedAt)
	if err != nil {
		t.Fatalf("insert: %v", err)
	}
}

func TestRefresh_LoadsActiveSitesAndIgnoresDeleted(t *testing.T) {
	db := newDB(t)
	insertSite(t, db, "active1", "strict", false)
	insertSite(t, db, "active2", "default", false)
	insertSite(t, db, "gone", "all", true)

	c := New(db, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := c.Refresh(context.Background()); err != nil {
		t.Fatalf("refresh: %v", err)
	}

	if _, ok := c.Get("active1"); !ok {
		t.Error("active1 missing")
	}
	if s, ok := c.Get("active2"); !ok || s.PrivacyMode != "default" {
		t.Errorf("active2 missing or wrong mode: %+v ok=%v", s, ok)
	}
	if _, ok := c.Get("gone"); ok {
		t.Error("soft-deleted site should not be in cache")
	}
}

func TestGet_BeforeRefresh_ReturnsEmpty(t *testing.T) {
	db := newDB(t)
	c := New(db, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if _, ok := c.Get("anything"); ok {
		t.Error("brand-new cache should be empty")
	}
}

func TestRefresh_UpdatesAfterDataChanges(t *testing.T) {
	db := newDB(t)
	c := New(db, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))

	insertSite(t, db, "first", "strict", false)
	if err := c.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := c.Get("first"); !ok {
		t.Fatal("first not loaded")
	}

	insertSite(t, db, "second", "strict", false)
	if err := c.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := c.Get("second"); !ok {
		t.Error("second not loaded after refresh")
	}
}
