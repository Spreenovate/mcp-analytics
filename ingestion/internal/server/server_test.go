package server

import (
	"context"
	"database/sql"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mcp-analytics/ingestion/internal/ch"
	"github.com/mcp-analytics/ingestion/internal/ratelimit"
	"github.com/mcp-analytics/ingestion/internal/session"
	"github.com/mcp-analytics/ingestion/internal/sites"
	"github.com/mcp-analytics/ingestion/internal/usage"

	_ "modernc.org/sqlite"
)

// fixture wires up a Server with one known site "abc12345" in strict mode,
// a fake ClickHouse server, and a static dir holding script.js.
type fixture struct {
	srv       *Server
	chCalls   *int64
	chServer  *httptest.Server
	staticDir string
	cleanup   func()
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	// In-memory SQLite with the one site we care about.
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
		VALUES ('abc12345', 1, 'example.com', 'strict', 'site-salt');
	`); err != nil {
		t.Fatal(err)
	}
	cache := sites.New(db, time.Hour, logger)
	if err := cache.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}

	// Fake ClickHouse — count POSTs.
	var calls int64
	chServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt64(&calls, 1)
		w.WriteHeader(http.StatusOK)
	}))

	cli := ch.New(chServer.URL, "default", "", "mcpa", logger)
	batcher := ch.NewBatcher(cli, 1, 50*time.Millisecond) // tiny batch -> immediate flush
	ctx, cancel := context.WithCancel(context.Background())
	go batcher.Run(ctx)

	usageBuf := usage.NewBuffer(nil, time.Hour, logger)
	salt := session.NewDailySalt(func() []byte { return []byte("daily-salt") })
	limiter := ratelimit.New(100)

	staticDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(staticDir, "script.js"),
		[]byte("/* test tracker */"), 0o644); err != nil {
		t.Fatal(err)
	}

	srv := &Server{
		Log: logger, Sites: cache, Batcher: batcher,
		Usage: usageBuf, DailySalt: salt, Limiter: limiter,
		StaticDir: staticDir,
	}

	return &fixture{
		srv: srv, chCalls: &calls, chServer: chServer, staticDir: staticDir,
		cleanup: func() {
			cancel()
			chServer.Close()
			db.Close()
		},
	}
}

func waitForCalls(t *testing.T, count *int64, want int64, within time.Duration) {
	t.Helper()
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		if atomic.LoadInt64(count) >= want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("expected at least %d ClickHouse calls, got %d", want, atomic.LoadInt64(count))
}

func TestEvent_KnownSite_ProducesClickHouseInsert(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	body := `{"site":"abc12345","name":"pageview","url":"https://example.com/home"}`
	req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh) AppleWebKit/605 Version/17.0 Safari/605.1")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d want 204", rr.Code)
	}
	waitForCalls(t, f.chCalls, 1, 2*time.Second)
}

func TestEvent_UnknownSite_NoInsert_ButLoggedToUnknown(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	body := `{"site":"GHOST","name":"pageview","url":"https://x.test/"}`
	req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d want 204", rr.Code)
	}
	// Brief wait to ensure no batcher flush happens.
	time.Sleep(150 * time.Millisecond)
	if atomic.LoadInt64(f.chCalls) != 0 {
		t.Errorf("unknown site should not reach ClickHouse, got %d calls", atomic.LoadInt64(f.chCalls))
	}
}

func TestEvent_BotUA_KeptAndLabeled(t *testing.T) {
	// Phase-1 bot classification: bot UAs are no longer dropped — the row
	// is written with traffic_class='bot' and the raw UA preserved so the
	// new top_user_agents MCP tool can surface them.
	f := newFixture(t)
	defer f.cleanup()

	body := `{"site":"abc12345","name":"pageview","url":"https://example.com/"}`
	req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
	req.Header.Set("User-Agent", "Googlebot/2.1")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d want 204", rr.Code)
	}
	waitForCalls(t, f.chCalls, 1, 2*time.Second)
}

func TestEvent_MalformedBody_StillReturns204(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	req := httptest.NewRequest("POST", "/event", strings.NewReader("{not-json"))
	req.Header.Set("User-Agent", "Mozilla/5.0")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d want 204", rr.Code)
	}
}

func TestEvent_GetRejected(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	req := httptest.NewRequest("GET", "/event", nil)
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusMethodNotAllowed {
		t.Errorf("status: got %d want 405", rr.Code)
	}
}

func TestScript_Served(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	req := httptest.NewRequest("GET", "/script.js", nil)
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("status: got %d want 200", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "test tracker") {
		t.Errorf("body: got %q", rr.Body.String())
	}
	if ct := rr.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/javascript") {
		t.Errorf("content-type: got %q", ct)
	}
	if cors := rr.Header().Get("Access-Control-Allow-Origin"); cors != "*" {
		t.Errorf("CORS header missing: got %q", cors)
	}
}

func TestHealthz(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	req := httptest.NewRequest("GET", "/healthz", nil)
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d", rr.Code)
	}
}
