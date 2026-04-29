package ch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"sync"
	"time"
)

type Client struct {
	BaseURL  string
	User     string
	Password string
	Database string

	HTTP *http.Client
	Log  *slog.Logger
}

// Event is the flat row shape we insert into mcpa.events via JSONEachRow.
type Event struct {
	SiteID         string    `json:"site_id"`
	Timestamp      string    `json:"timestamp"`
	EventName      string    `json:"event_name"`
	SessionID      uint64    `json:"session_id"`
	VisitorID      uint64    `json:"visitor_id"`
	URLPath        string    `json:"url_path"`
	URLHost        string    `json:"url_host"`
	ReferrerHost   string    `json:"referrer_host"`
	ReferrerPath   string    `json:"referrer_path"`
	UTMSource      string    `json:"utm_source"`
	UTMMedium      string    `json:"utm_medium"`
	UTMCampaign    string    `json:"utm_campaign"`
	Browser        string    `json:"browser"`
	BrowserVersion string    `json:"browser_version"`
	OS             string    `json:"os"`
	DeviceType     string    `json:"device_type"`
	Country        string    `json:"country"`
	Region         string    `json:"region"`
	City           string    `json:"city"`
	PropKeys       []string  `json:"prop_keys"`
	PropValues     []string  `json:"prop_values"`
	TrafficClass   string    `json:"traffic_class"`     // 'user' or 'bot' in Phase 1
	UserAgent      string    `json:"user_agent"`        // raw UA — kept for retroactive classification
	// Stufe-2 client-side signals. All from privacy-clean Web APIs.
	Timezone          string `json:"timezone"`
	Language          string `json:"language"`
	ColorScheme       string `json:"color_scheme"`        // 'light' | 'dark' | ''
	ViewportW         uint16 `json:"viewport_w"`
	ViewportH         uint16 `json:"viewport_h"`
	EngagementSeconds uint32 `json:"engagement_seconds"`  // populated on event_name='engagement' rows
	ScrollDepth       uint8  `json:"scroll_depth"`        // 0..100, same
	IngestedAt     time.Time `json:"-"`
}

func New(baseURL, user, password, database string, log *slog.Logger) *Client {
	return &Client{
		BaseURL:  baseURL,
		User:     user,
		Password: password,
		Database: database,
		HTTP:     &http.Client{Timeout: 10 * time.Second},
		Log:      log,
	}
}

// Insert ships rows using ClickHouse async_insert. We intentionally do not wait
// for server-side flush, because durability at the row level is not critical
// for analytics — we prefer throughput and low p99 ingest latency.
func (c *Client) Insert(ctx context.Context, events []Event) error {
	if len(events) == 0 {
		return nil
	}

	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	for i := range events {
		if err := enc.Encode(&events[i]); err != nil {
			return err
		}
	}

	q := url.Values{}
	q.Set("query",
		fmt.Sprintf("INSERT INTO %s.events FORMAT JSONEachRow", c.Database))
	q.Set("async_insert", "1")
	q.Set("wait_for_async_insert", "0")

	req, err := http.NewRequestWithContext(ctx, "POST",
		c.BaseURL+"/?"+q.Encode(), &buf)
	if err != nil {
		return err
	}
	if c.User != "" {
		req.SetBasicAuth(c.User, c.Password)
	}
	req.Header.Set("Content-Type", "application/x-ndjson")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("clickhouse insert failed: %d %s", resp.StatusCode, string(body))
	}
	return nil
}

// Batcher buffers events and flushes them on size or interval.
type Batcher struct {
	cli      *Client
	maxSize  int
	interval time.Duration

	mu  sync.Mutex
	buf []Event

	in chan Event
}

func NewBatcher(cli *Client, maxSize int, interval time.Duration) *Batcher {
	return &Batcher{
		cli:      cli,
		maxSize:  maxSize,
		interval: interval,
		in:       make(chan Event, maxSize*4),
	}
}

func (b *Batcher) Submit(ev Event) {
	select {
	case b.in <- ev:
	default:
		// Channel full — drop to protect the server. Caller already 204'd the client.
		b.cli.Log.Warn("ingest channel full, dropping event", "site", ev.SiteID)
	}
}

func (b *Batcher) Run(ctx context.Context) {
	t := time.NewTicker(b.interval)
	defer t.Stop()

	for {
		select {
		case <-ctx.Done():
			b.flush(context.Background())
			return
		case ev := <-b.in:
			b.mu.Lock()
			b.buf = append(b.buf, ev)
			full := len(b.buf) >= b.maxSize
			b.mu.Unlock()
			if full {
				b.flush(ctx)
			}
		case <-t.C:
			b.flush(ctx)
		}
	}
}

func (b *Batcher) flush(ctx context.Context) {
	b.mu.Lock()
	if len(b.buf) == 0 {
		b.mu.Unlock()
		return
	}
	batch := b.buf
	b.buf = make([]Event, 0, b.maxSize)
	b.mu.Unlock()

	if err := b.cli.Insert(ctx, batch); err != nil {
		b.cli.Log.Error("clickhouse insert failed", "err", err, "size", len(batch))
	}
}
