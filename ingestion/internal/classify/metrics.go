package classify

import (
	"sync"
	"sync/atomic"
	"time"
)

// Metrics holds the counters/gauges the classifier exposes for
// observability. Kept dependency-free (no Prometheus client) so the
// /healthz endpoint can render them as plain JSON. If we ever add
// real Prom export, swap the internals — the public API is stable.
type Metrics struct {
	// RefreshTotal counts refresh attempts by outcome:
	// "ok" / "none" (all sources failed) / "rejected_shrink" (sanity-check failed).
	RefreshTotal *labeledCounter

	// RefreshFailedTotal counts per-source fetch/parse failures.
	RefreshFailedTotal *sourceCounter

	// CIDRsLoaded tracks how many CIDRs each source contributes to the
	// currently-live trie.
	CIDRsLoaded *sourceGauge

	// RefreshAgeSeconds is the unix timestamp of the last successful
	// refresh. Read as `time.Now().Unix() - value` to derive age.
	RefreshAgeSeconds *unixTimestampGauge
}

// NewMetrics returns an empty, ready-to-use Metrics struct.
func NewMetrics() *Metrics {
	return &Metrics{
		RefreshTotal:       newLabeledCounter(),
		RefreshFailedTotal: newSourceCounter(),
		CIDRsLoaded:        newSourceGauge(),
		RefreshAgeSeconds:  &unixTimestampGauge{},
	}
}

// Snapshot returns the current state for /healthz JSON.
func (m *Metrics) Snapshot() map[string]any {
	now := time.Now()
	last := m.RefreshAgeSeconds.Get()
	ageSeconds := int64(-1)
	if last > 0 {
		ageSeconds = now.Unix() - last
	}
	return map[string]any{
		"refresh_total":         m.RefreshTotal.Snapshot(),
		"refresh_failed_total":  m.RefreshFailedTotal.Snapshot(),
		"cidrs_loaded":          m.CIDRsLoaded.Snapshot(),
		"cidrs_loaded_total":    m.CIDRsLoaded.Total(),
		"last_refresh_unix":     last,
		"last_refresh_age_secs": ageSeconds,
	}
}

// --- counter primitives ----------------------------------------------

type labeledCounter struct {
	mu     sync.Mutex
	values map[string]*atomic.Int64
}

func newLabeledCounter() *labeledCounter {
	return &labeledCounter{values: make(map[string]*atomic.Int64)}
}

func (c *labeledCounter) WithLabel(label string) *atomic.Int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	v, ok := c.values[label]
	if !ok {
		v = &atomic.Int64{}
		c.values[label] = v
	}
	return v
}

func (c *labeledCounter) Snapshot() map[string]int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make(map[string]int64, len(c.values))
	for k, v := range c.values {
		out[k] = v.Load()
	}
	return out
}

type sourceCounter struct{ inner *labeledCounter }

func newSourceCounter() *sourceCounter { return &sourceCounter{inner: newLabeledCounter()} }
func (c *sourceCounter) WithSource(name string) *atomic.Int64 {
	return c.inner.WithLabel(name)
}
func (c *sourceCounter) Snapshot() map[string]int64 { return c.inner.Snapshot() }

// sourceGauge: per-source absolute value (last set wins, no Add).
type sourceGauge struct {
	mu     sync.Mutex
	values map[string]*atomic.Int64
}

func newSourceGauge() *sourceGauge {
	return &sourceGauge{values: make(map[string]*atomic.Int64)}
}

// WithSource returns the gauge for the given source name, creating it
// if absent.
func (g *sourceGauge) WithSource(name string) *atomic.Int64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	v, ok := g.values[name]
	if !ok {
		v = &atomic.Int64{}
		g.values[name] = v
	}
	return v
}

// Reset clears all per-source gauge values. Used after a successful
// refresh to ensure stale source names don't linger.
func (g *sourceGauge) Reset() {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.values = make(map[string]*atomic.Int64)
}

func (g *sourceGauge) Snapshot() map[string]int64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	out := make(map[string]int64, len(g.values))
	for k, v := range g.values {
		out[k] = v.Load()
	}
	return out
}

func (g *sourceGauge) Total() int64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	var total int64
	for _, v := range g.values {
		total += v.Load()
	}
	return total
}

// unixTimestampGauge stores a single unix-second value.
type unixTimestampGauge struct{ ts atomic.Int64 }

func (g *unixTimestampGauge) Get() int64 { return g.ts.Load() }
func (g *unixTimestampGauge) SetNow(now func() time.Time) {
	if now == nil {
		now = time.Now
	}
	g.ts.Store(now().Unix())
}
