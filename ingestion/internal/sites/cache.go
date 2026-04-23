package sites

import (
	"context"
	"database/sql"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"
)

type Site struct {
	SiteID      string
	UserID      int64
	Domain      string
	PrivacyMode string
	SiteSalt    string
}

// Cache keeps an in-memory snapshot of non-deleted sites.
// Reads are lock-free (atomic pointer swap on refresh).
type Cache struct {
	db       *sql.DB
	interval time.Duration
	current  atomic.Pointer[map[string]Site]
	log      *slog.Logger
}

func New(db *sql.DB, interval time.Duration, log *slog.Logger) *Cache {
	c := &Cache{db: db, interval: interval, log: log}
	empty := map[string]Site{}
	c.current.Store(&empty)
	return c
}

func (c *Cache) Get(siteID string) (Site, bool) {
	m := *c.current.Load()
	s, ok := m[siteID]
	return s, ok
}

func (c *Cache) Refresh(ctx context.Context) error {
	rows, err := c.db.QueryContext(ctx,
		`SELECT site_id, user_id, domain, privacy_mode, site_salt
		   FROM sites
		   WHERE deleted_at IS NULL`)
	if err != nil {
		return err
	}
	defer rows.Close()

	next := make(map[string]Site, 64)
	for rows.Next() {
		var s Site
		if err := rows.Scan(&s.SiteID, &s.UserID, &s.Domain, &s.PrivacyMode, &s.SiteSalt); err != nil {
			return err
		}
		next[s.SiteID] = s
	}
	if err := rows.Err(); err != nil {
		return err
	}

	c.current.Store(&next)
	return nil
}

// Run refreshes the cache in a loop until ctx is cancelled.
func (c *Cache) Run(ctx context.Context) {
	if err := c.Refresh(ctx); err != nil {
		c.log.Error("initial site cache refresh failed", "err", err)
	}

	t := time.NewTicker(c.interval)
	defer t.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			var wg sync.WaitGroup
			wg.Add(1)
			go func() {
				defer wg.Done()
				if err := c.Refresh(ctx); err != nil {
					c.log.Warn("site cache refresh failed", "err", err)
				}
			}()
			wg.Wait()
		}
	}
}
