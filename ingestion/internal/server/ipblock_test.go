package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mcp-analytics/ingestion/internal/ipblock"
	"github.com/mcp-analytics/ingestion/internal/usage"
)

func TestEvent_UnknownSite_RecordsWithIPBlocker(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	var blockFires atomic.Int32
	f.srv.IPBlock = ipblock.New(ipblock.Options{
		Window: time.Hour, Threshold: 3, BlockFor: time.Hour,
		OnBlock: func(_ string, _ int, _ time.Time) { blockFires.Add(1) },
	})

	send := func(ua, siteID string) int {
		body := `{"site":"` + siteID + `","name":"pageview","url":"https://x.test/"}`
		req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
		req.Header.Set("User-Agent", ua)
		req.Header.Set("X-Forwarded-For", "9.9.9.9")
		rr := httptest.NewRecorder()
		f.srv.Routes().ServeHTTP(rr, req)
		return rr.Code
	}

	realUA := "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605"
	for _, s := range []string{"aaa", "bbb", "ccc", "ddd"} {
		if code := send(realUA, s); code != http.StatusNoContent {
			t.Errorf("got %d, want 204", code)
		}
	}

	if !f.srv.IPBlock.IsBlocked("9.9.9.9") {
		t.Fatal("IP should be blocked after 4 unique unknown site_ids with threshold=3")
	}
	if blockFires.Load() != 1 {
		t.Errorf("OnBlock fires = %d, want 1", blockFires.Load())
	}
}

func TestEvent_BlockedIP_IsDroppedBeforeSiteLookup(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	f.srv.IPBlock = ipblock.New(ipblock.Options{
		Window: time.Hour, Threshold: 1, BlockFor: time.Hour,
	})

	realUA := "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605"

	// Burn past the threshold quickly.
	for _, s := range []string{"x1", "x2"} {
		body := `{"site":"` + s + `","name":"pageview","url":"https://x.test/"}`
		req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
		req.Header.Set("User-Agent", realUA)
		req.Header.Set("X-Forwarded-For", "7.7.7.7")
		f.srv.Routes().ServeHTTP(httptest.NewRecorder(), req)
	}
	if !f.srv.IPBlock.IsBlocked("7.7.7.7") {
		t.Fatal("precondition: 7.7.7.7 should be blocked")
	}

	// Now send a request for a VALID site from that IP: it must be dropped
	// (no ClickHouse insert) even though the site exists.
	before := atomic.LoadInt64(f.chCalls)
	body := `{"site":"abc12345","name":"pageview","url":"https://example.com/"}`
	req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
	req.Header.Set("User-Agent", realUA)
	req.Header.Set("X-Forwarded-For", "7.7.7.7")
	rr := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Errorf("status: got %d, want 204", rr.Code)
	}
	time.Sleep(150 * time.Millisecond)
	if after := atomic.LoadInt64(f.chCalls); after != before {
		t.Errorf("blocked IP produced a ClickHouse insert (before=%d, after=%d)", before, after)
	}
}

func TestEvent_KnownSite_DoesNotCountAgainstIPBlock(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	f.srv.IPBlock = ipblock.New(ipblock.Options{
		Window: time.Hour, Threshold: 2, BlockFor: time.Hour,
	})

	realUA := "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605"
	for i := 0; i < 10; i++ {
		body := `{"site":"abc12345","name":"pageview","url":"https://example.com/"}`
		req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
		req.Header.Set("User-Agent", realUA)
		req.Header.Set("X-Forwarded-For", "8.8.8.8")
		f.srv.Routes().ServeHTTP(httptest.NewRecorder(), req)
	}
	if f.srv.IPBlock.IsBlocked("8.8.8.8") {
		t.Error("legitimate hits to a known site must not trigger IP block")
	}
}

func TestEvent_OnBlockCallback_QueuesAbuseAlertInBuffer(t *testing.T) {
	f := newFixture(t)
	defer f.cleanup()

	f.srv.IPBlock = ipblock.New(ipblock.Options{
		Window: time.Hour, Threshold: 2, BlockFor: time.Hour,
		OnBlock: func(ip string, uniq int, at time.Time) {
			f.srv.Usage.RecordAbuse(usage.AbuseAlert{
				IP: ip, UniqueSites: uniq, BlockedUntil: at.Add(time.Hour), At: at,
			})
		},
	})

	realUA := "Mozilla/5.0 (Macintosh) AppleWebKit Version/17 Safari/605"
	for _, s := range []string{"qq", "ww", "ee"} {
		body := `{"site":"` + s + `","name":"pageview","url":"https://x.test/"}`
		req := httptest.NewRequest("POST", "/event", strings.NewReader(body))
		req.Header.Set("User-Agent", realUA)
		req.Header.Set("X-Forwarded-For", "6.6.6.6")
		f.srv.Routes().ServeHTTP(httptest.NewRecorder(), req)
	}

	// The Buffer's internal slice should have exactly one queued alert.
	if got := f.srv.Usage.PendingAbuseAlerts(); got != 1 {
		t.Errorf("pending abuse alerts: got %d, want 1", got)
	}
}
