package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/mcp-analytics/ingestion/internal/ch"
	"github.com/mcp-analytics/ingestion/internal/ratelimit"
	"github.com/mcp-analytics/ingestion/internal/session"
	"github.com/mcp-analytics/ingestion/internal/sites"
	"github.com/mcp-analytics/ingestion/internal/usage"

	_ "modernc.org/sqlite"
)

// allModeFixture wires a Server with ONE site in "all" privacy mode
// and a ClickHouse httptest sink that parses inserted rows.
type allModeFixture struct {
	srv    *Server
	rows   *[]ch.Event
	rowsMu *sync.Mutex
	close  func()
}

func newAllModeFixture(t *testing.T) *allModeFixture {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		CREATE TABLE sites (
			id INTEGER PRIMARY KEY, site_id TEXT, user_id INTEGER,
			domain TEXT, privacy_mode TEXT, site_salt TEXT, deleted_at DATETIME
		);
		INSERT INTO sites (site_id, user_id, domain, privacy_mode, site_salt)
		VALUES ('allmode1', 1, 'example.com', 'all', 'site-salt');
	`); err != nil {
		t.Fatal(err)
	}
	cache := sites.New(db, time.Hour, logger)
	if err := cache.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}

	var rows []ch.Event
	var mu sync.Mutex
	chServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		dec := json.NewDecoder(strings.NewReader(string(body)))
		for {
			var ev ch.Event
			if err := dec.Decode(&ev); err != nil {
				break
			}
			mu.Lock()
			rows = append(rows, ev)
			mu.Unlock()
		}
		w.WriteHeader(http.StatusOK)
	}))

	cli := ch.New(chServer.URL, "default", "", "mcpa", logger)
	batcher := ch.NewBatcher(cli, 1, 30*time.Millisecond)
	ctx, cancel := context.WithCancel(context.Background())
	go batcher.Run(ctx)

	staticDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(staticDir, "script.js"), []byte("/*t*/"), 0o644)

	srv := &Server{
		Log: logger, Sites: cache, Batcher: batcher,
		Usage:     usage.NewBuffer(nil, time.Hour, logger),
		DailySalt: session.NewDailySalt(func() []byte { return []byte("daily") }),
		Limiter:   ratelimit.New(100),
		StaticDir: staticDir,
	}
	return &allModeFixture{
		srv: srv, rows: &rows, rowsMu: &mu,
		close: func() { cancel(); chServer.Close(); db.Close() },
	}
}

func waitForRow(t *testing.T, f *allModeFixture, within time.Duration) ch.Event {
	t.Helper()
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		f.rowsMu.Lock()
		n := len(*f.rows)
		f.rowsMu.Unlock()
		if n > 0 {
			f.rowsMu.Lock()
			defer f.rowsMu.Unlock()
			return (*f.rows)[0]
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("no row reached ClickHouse within deadline")
	return ch.Event{}
}

func sendEventJSON(f *allModeFixture, body string) int {
	req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605")
	req.Header.Set("X-Forwarded-For", "203.0.113.9")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)
	return rr.Code
}

func TestAllMode_ValidVisitorIDIsHashedAndUsed(t *testing.T) {
	f := newAllModeFixture(t)
	defer f.close()

	body := `{"site":"allmode1","name":"pageview","url":"https://example.com/",` +
		`"visitor_id":"abcdef0123456789abcdef0123456789"}`
	if code := sendEventJSON(f, body); code != http.StatusNoContent {
		t.Fatalf("status: got %d want 204", code)
	}

	row := waitForRow(t, f, 2*time.Second)
	expected := session.Compute([]byte("site-salt"), []byte("abcdef0123456789abcdef0123456789"))
	if row.VisitorID != expected {
		t.Errorf("visitor_id: got %d want %d", row.VisitorID, expected)
	}
	if row.SessionID == 0 {
		t.Error("session_id should be non-zero in all mode")
	}
}

func TestAllMode_InvalidVisitorIDFallsBackToHash(t *testing.T) {
	f := newAllModeFixture(t)
	defer f.close()

	body := `{"site":"allmode1","name":"pageview","url":"https://example.com/",` +
		`"visitor_id":"<script>/malicious"}`
	sendEventJSON(f, body)

	row := waitForRow(t, f, 2*time.Second)
	fallback := session.DefaultVisitorID([]byte("site-salt"), "203.0.113.9",
		"Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605", "allmode1")
	if row.VisitorID != fallback {
		t.Errorf("expected fallback hash %d, got %d", fallback, row.VisitorID)
	}
}

func TestAllMode_MissingVisitorIDFallsBackToHash(t *testing.T) {
	f := newAllModeFixture(t)
	defer f.close()

	body := `{"site":"allmode1","name":"pageview","url":"https://example.com/"}`
	sendEventJSON(f, body)

	row := waitForRow(t, f, 2*time.Second)
	fallback := session.DefaultVisitorID([]byte("site-salt"), "203.0.113.9",
		"Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605", "allmode1")
	if row.VisitorID != fallback {
		t.Errorf("expected fallback hash %d, got %d", fallback, row.VisitorID)
	}
}
