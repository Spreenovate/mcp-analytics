// Package ipblock tracks, per client IP, how many *distinct* unknown
// site_ids have been sent to /event inside a rolling window. When an IP
// crosses the threshold, it is blocked for `blockFor`. While blocked,
// requests from that IP are dropped early.
//
// The tracker is in-memory only — good enough for a single-host MVP.
// Crossings are reported via an OnBlock callback so the caller can
// persist an alert (we write one row into the `abuse_events` SQLite
// table so Rails can email the operator asynchronously).
package ipblock

import (
	"sync"
	"time"
)

type Tracker struct {
	window     time.Duration
	threshold  int
	blockFor   time.Duration
	onBlock    func(ip string, uniqueSites int, at time.Time)
	now        func() time.Time

	mu      sync.Mutex
	entries map[string]*entry
}

type entry struct {
	// Map of unknown site_id → most recent timestamp within the window.
	sites        map[string]time.Time
	blockedUntil time.Time
	// alertedFor prevents re-firing OnBlock for the same block period.
	alertedFor time.Time
}

type Options struct {
	Window    time.Duration
	Threshold int
	BlockFor  time.Duration
	OnBlock   func(ip string, uniqueSites int, at time.Time)
	Now       func() time.Time // injectable for tests
}

func New(opts Options) *Tracker {
	if opts.Window == 0 {
		opts.Window = time.Hour
	}
	if opts.Threshold == 0 {
		opts.Threshold = 100
	}
	if opts.BlockFor == 0 {
		opts.BlockFor = time.Hour
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	return &Tracker{
		window:    opts.Window,
		threshold: opts.Threshold,
		blockFor:  opts.BlockFor,
		onBlock:   opts.OnBlock,
		now:       opts.Now,
		entries:   make(map[string]*entry, 64),
	}
}

// IsBlocked reports whether `ip` is currently blocked.
func (t *Tracker) IsBlocked(ip string) bool {
	if ip == "" {
		return false
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	e, ok := t.entries[ip]
	if !ok {
		return false
	}
	return t.now().Before(e.blockedUntil)
}

// RecordUnknown records that `ip` sent an event for a non-existent
// site_id. If this pushes the distinct count above the threshold within
// the window, the IP becomes blocked and OnBlock fires (once per block).
func (t *Tracker) RecordUnknown(ip, siteIDAttempted string) {
	if ip == "" || siteIDAttempted == "" {
		return
	}
	now := t.now()
	cutoff := now.Add(-t.window)

	t.mu.Lock()
	defer t.mu.Unlock()

	e, ok := t.entries[ip]
	if !ok {
		e = &entry{sites: make(map[string]time.Time, 8)}
		t.entries[ip] = e
	}

	// Evict sites outside the window.
	for sid, ts := range e.sites {
		if ts.Before(cutoff) {
			delete(e.sites, sid)
		}
	}

	e.sites[siteIDAttempted] = now

	if len(e.sites) > t.threshold && now.After(e.blockedUntil) {
		e.blockedUntil = now.Add(t.blockFor)
		if e.alertedFor != e.blockedUntil && t.onBlock != nil {
			e.alertedFor = e.blockedUntil
			uniq := len(e.sites)
			// Release the lock while the callback runs — it may do I/O.
			t.mu.Unlock()
			t.onBlock(ip, uniq, now)
			t.mu.Lock()
		}
	}
}

// Sweep drops stale IP entries to keep memory bounded.
// Call periodically from the owner goroutine.
func (t *Tracker) Sweep() {
	now := t.now()
	cutoff := now.Add(-t.window)

	t.mu.Lock()
	defer t.mu.Unlock()
	for ip, e := range t.entries {
		if !e.blockedUntil.IsZero() && now.Before(e.blockedUntil) {
			continue // keep blocked IPs around
		}
		// Drop if there's nothing in-window and no active block.
		anyFresh := false
		for _, ts := range e.sites {
			if ts.After(cutoff) {
				anyFresh = true
				break
			}
		}
		if !anyFresh {
			delete(t.entries, ip)
		}
	}
}
