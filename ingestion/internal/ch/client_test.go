package ch

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func newTestClient(handler http.HandlerFunc) (*Client, *httptest.Server) {
	srv := httptest.NewServer(handler)
	c := New(srv.URL, "default", "", "mcpa", slog.New(slog.NewTextHandler(io.Discard, nil)))
	return c, srv
}

func TestInsert_NoEvents_NoCall(t *testing.T) {
	called := false
	c, srv := newTestClient(func(_ http.ResponseWriter, _ *http.Request) { called = true })
	defer srv.Close()

	if err := c.Insert(context.Background(), nil); err != nil {
		t.Fatalf("err: %v", err)
	}
	if called {
		t.Error("Insert with no events should not call the server")
	}
}

func TestInsert_SendsJSONEachRow(t *testing.T) {
	var got struct {
		query string
		body  string
	}
	c, srv := newTestClient(func(w http.ResponseWriter, r *http.Request) {
		got.query = r.URL.Query().Get("query")
		b, _ := io.ReadAll(r.Body)
		got.body = string(b)
		w.WriteHeader(http.StatusOK)
	})
	defer srv.Close()

	err := c.Insert(context.Background(), []Event{
		{SiteID: "abc", EventName: "pageview", URLPath: "/x"},
		{SiteID: "abc", EventName: "click", URLPath: "/y"},
	})
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if !strings.Contains(got.query, "INSERT INTO mcpa.events FORMAT JSONEachRow") {
		t.Errorf("query missing INSERT statement, got %q", got.query)
	}
	if !strings.Contains(got.body, `"site_id":"abc"`) || strings.Count(got.body, "\n") < 2 {
		t.Errorf("expected NDJSON body with two rows, got %q", got.body)
	}
}

func TestInsert_AsyncFlagsPresent(t *testing.T) {
	c, srv := newTestClient(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("async_insert") != "1" {
			t.Errorf("async_insert flag missing")
		}
		if r.URL.Query().Get("wait_for_async_insert") != "0" {
			t.Errorf("wait_for_async_insert should be 0")
		}
		w.WriteHeader(http.StatusOK)
	})
	defer srv.Close()
	_ = c.Insert(context.Background(), []Event{{SiteID: "a"}})
}

func TestInsert_ServerError_Bubbles(t *testing.T) {
	c, srv := newTestClient(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = io.WriteString(w, "boom")
	})
	defer srv.Close()

	err := c.Insert(context.Background(), []Event{{SiteID: "a"}})
	if err == nil {
		t.Fatal("expected error on 500 response")
	}
	if !strings.Contains(err.Error(), "500") {
		t.Errorf("err should mention status, got: %v", err)
	}
}

func TestBatcher_FlushesOnSize(t *testing.T) {
	flushes := 0
	c, srv := newTestClient(func(w http.ResponseWriter, _ *http.Request) {
		flushes++
		w.WriteHeader(http.StatusOK)
	})
	defer srv.Close()

	b := NewBatcher(c, 3, time.Hour)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go b.Run(ctx)

	for i := 0; i < 3; i++ {
		b.Submit(Event{SiteID: "x"})
	}

	// Allow the Run loop to consume + flush.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && flushes == 0 {
		time.Sleep(20 * time.Millisecond)
	}
	if flushes == 0 {
		t.Fatal("size-based flush never happened")
	}
}
