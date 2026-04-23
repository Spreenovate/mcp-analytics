package usage

import (
	"context"
	"database/sql"
	"log/slog"
	"sync"
	"time"
)

// Buffer accumulates hit counts per (site_id, month) in memory and periodically
// flushes them into SQLite. Rails reads usage_counters for MCP queries; we write
// to the same table with UPSERT semantics. Flush interval is 30s by default —
// low enough to feel fresh, high enough to avoid contention on SQLite.
type Buffer struct {
	db            *sql.DB
	flushInterval time.Duration
	log           *slog.Logger

	mu       sync.Mutex
	counters map[key]int64

	unknownCounters map[unknownKey]int64
}

type key struct {
	SiteID string
	Month  string // "YYYY-MM-01"
}

type unknownKey struct {
	SiteIDAttempted string
	Hour            string // "YYYY-MM-DD HH:00:00 UTC"
}

func NewBuffer(db *sql.DB, interval time.Duration, log *slog.Logger) *Buffer {
	return &Buffer{
		db:              db,
		flushInterval:   interval,
		log:             log,
		counters:        make(map[key]int64, 64),
		unknownCounters: make(map[unknownKey]int64, 64),
	}
}

func (b *Buffer) Bump(siteID string, at time.Time) {
	k := key{SiteID: siteID, Month: at.UTC().Format("2006-01-02")[:8] + "01"}
	b.mu.Lock()
	b.counters[k]++
	b.mu.Unlock()
}

func (b *Buffer) BumpUnknown(siteIDAttempted string, at time.Time) {
	hour := at.UTC().Truncate(time.Hour).Format("2006-01-02 15:04:05")
	k := unknownKey{SiteIDAttempted: siteIDAttempted, Hour: hour}
	b.mu.Lock()
	b.unknownCounters[k]++
	b.mu.Unlock()
}

func (b *Buffer) Run(ctx context.Context) {
	t := time.NewTicker(b.flushInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			b.flush(context.Background())
			return
		case <-t.C:
			b.flush(ctx)
		}
	}
}

func (b *Buffer) flush(ctx context.Context) {
	b.mu.Lock()
	pending := b.counters
	unknown := b.unknownCounters
	b.counters = make(map[key]int64, len(pending))
	b.unknownCounters = make(map[unknownKey]int64, len(unknown))
	b.mu.Unlock()

	if len(pending) == 0 && len(unknown) == 0 {
		return
	}

	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		b.log.Warn("usage flush begin failed", "err", err)
		b.merge(pending, unknown)
		return
	}

	now := time.Now().UTC().Format("2006-01-02 15:04:05.000")

	for k, n := range pending {
		// Emulate UPSERT. SQLite supports ON CONFLICT since 3.24.
		_, err := tx.ExecContext(ctx,
			`INSERT INTO usage_counters (site_id, month, hit_count, created_at, updated_at)
			   VALUES (?, ?, ?, ?, ?)
			 ON CONFLICT(site_id, month) DO UPDATE
			   SET hit_count = hit_count + excluded.hit_count,
			       updated_at = excluded.updated_at`,
			k.SiteID, k.Month, n, now, now)
		if err != nil {
			b.log.Warn("usage upsert failed", "err", err, "site", k.SiteID)
		}
	}

	for k, n := range unknown {
		_, err := tx.ExecContext(ctx,
			`INSERT INTO unknown_site_hits (site_id_attempted, hour, hit_count, created_at, updated_at)
			   VALUES (?, ?, ?, ?, ?)
			 ON CONFLICT(site_id_attempted, hour) DO UPDATE
			   SET hit_count = hit_count + excluded.hit_count,
			       updated_at = excluded.updated_at`,
			k.SiteIDAttempted, k.Hour, n, now, now)
		if err != nil {
			b.log.Warn("unknown_site_hits upsert failed", "err", err)
		}
	}

	if err := tx.Commit(); err != nil {
		b.log.Warn("usage flush commit failed", "err", err)
		b.merge(pending, unknown)
	}
}

// merge re-adds counters back into the live buffer after a failed flush.
func (b *Buffer) merge(pending map[key]int64, unknown map[unknownKey]int64) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for k, n := range pending {
		b.counters[k] += n
	}
	for k, n := range unknown {
		b.unknownCounters[k] += n
	}
}
