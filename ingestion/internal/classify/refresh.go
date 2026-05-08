package classify

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// RefreshConfig tunes the background-refresh loop. Defaults match what
// main() uses; tests pass smaller values.
type RefreshConfig struct {
	// Interval between refresh attempts. Default 6h.
	Interval time.Duration

	// HTTPTimeout per source-fetch. Default 15s.
	HTTPTimeout time.Duration

	// MinShrinkRatio: if a fresh fetch produces fewer than
	// MinShrinkRatio * len(previous) entries (across all sources),
	// reject the new trie and keep the old one. Catches the
	// "OpenAI returns empty array" silent-regression case. Default 0.5.
	MinShrinkRatio float64

	// SourceFn returns the list of sources to fetch. Override in tests.
	// Default classify.Sources.
	SourceFn func() []Source

	// HTTPClient used for fetches. Default http.DefaultClient with
	// HTTPTimeout applied.
	HTTPClient *http.Client

	// Log used for refresh chatter. nil → slog.Default.
	Log *slog.Logger

	// Now used for tests. Default time.Now.
	Now func() time.Time
}

func (c *RefreshConfig) defaults() {
	if c.Interval == 0 {
		c.Interval = 6 * time.Hour
	}
	if c.HTTPTimeout == 0 {
		c.HTTPTimeout = 15 * time.Second
	}
	if c.MinShrinkRatio == 0 {
		c.MinShrinkRatio = 0.5
	}
	if c.SourceFn == nil {
		c.SourceFn = Sources
	}
	if c.HTTPClient == nil {
		c.HTTPClient = &http.Client{
			Timeout: c.HTTPTimeout,
			// Lock the redirect chain to HTTPS only — defense against
			// a vendor accidentally (or maliciously) redirecting to an
			// HTTP URL, which would strip TLS. Public IP-range JSONs
			// are HTTPS in practice; same-scheme redirects within
			// the vendor's own domain are fine.
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if req.URL.Scheme != "https" {
					return fmt.Errorf("redirect to non-HTTPS rejected: %s",
						req.URL)
				}
				// Allow up to 5 prior hops (this is the 6th request, but
				// stricter than Go's default-10 and bounded enough for
				// any legitimate vendor CDN chain).
				if len(via) >= 5 {
					return fmt.Errorf("too many redirects (%d)", len(via))
				}
				return nil
			},
		}
	}
	if c.Log == nil {
		c.Log = slog.Default()
	}
	if c.Now == nil {
		c.Now = time.Now
	}
}

// Refresher fetches sources, parses them, builds a Trie and atomic-
// swaps it into a target *AtomicLookup. Holds telemetry for ops.
//
// prevSwapTotal caches the entry count of the LAST trie that was
// successfully swapped in (not the current gauge total — that gets
// reset before swap). Used by the MinShrinkRatio sanity-check so a
// partial-success refresh that legitimately shrunk the data doesn't
// get rejected against a zero baseline. Mutated only by RunOnce on
// the refresh goroutine.
type Refresher struct {
	cfg           RefreshConfig
	target        *AtomicLookup
	mx            *Metrics
	prevSwapTotal int64
}

// NewRefresher creates a Refresher. Caller is responsible for storing
// an initial fallback trie into target before starting the refresh
// goroutine — see classify.Bootstrap.
func NewRefresher(target *AtomicLookup, mx *Metrics, cfg RefreshConfig) *Refresher {
	cfg.defaults()
	return &Refresher{cfg: cfg, target: target, mx: mx}
}

// RunOnce performs a single refresh attempt. Returns nil on success,
// or an error describing why the swap was skipped (network, parse,
// sanity-check fail).
func (r *Refresher) RunOnce(ctx context.Context) error {
	sources := r.cfg.SourceFn()
	if len(sources) == 0 {
		return errors.New("no sources configured")
	}

	var entries []TrieEntry
	freshPerSource := map[string]int64{}
	var okCount, failCount int

	for _, src := range sources {
		nets, err := r.fetchSource(ctx, src)
		if err != nil {
			r.cfg.Log.Warn("classify refresh source failed",
				"source", src.Name, "err", err)
			r.mx.RefreshFailedTotal.WithSource(src.Name).Add(1)
			failCount++
			continue
		}
		okCount++
		freshPerSource[src.Name] = int64(len(nets))
		for _, n := range nets {
			entries = append(entries, TrieEntry{
				Net:          n,
				Class:        src.Class,
				Provider:     src.Provider,
				IsCloudInfra: src.IsCloudInfra,
			})
		}
	}

	if okCount == 0 {
		r.mx.RefreshTotal.WithLabel("none").Add(1)
		return errors.New("all sources failed")
	}

	// Sanity-check against the LAST swap's total, not the current
	// gauge value — RunOnce resets the gauges as part of the swap, so
	// reading them is correct only on the first refresh after restart
	// (where prevSwapTotal is also 0). The cached field survives those
	// restarts naturally because the Refresher itself is process-
	// scoped.
	freshTotal := int64(len(entries))
	if r.prevSwapTotal > 0 {
		ratio := float64(freshTotal) / float64(r.prevSwapTotal)
		if ratio < r.cfg.MinShrinkRatio {
			r.mx.RefreshTotal.WithLabel("rejected_shrink").Add(1)
			return fmt.Errorf(
				"refresh rejected: new=%d prev=%d ratio=%.2f threshold=%.2f",
				freshTotal, r.prevSwapTotal, ratio, r.cfg.MinShrinkRatio)
		}
	}

	// Swap-in approved — now mutate the gauge to reflect the new live
	// state and cache the count for next time.
	r.mx.CIDRsLoaded.Reset()
	for name, n := range freshPerSource {
		r.mx.CIDRsLoaded.WithSource(name).Store(n)
	}

	r.target.Store(NewTrie(entries))
	r.prevSwapTotal = freshTotal
	if failCount > 0 {
		// Partial success: some sources contributed, others failed.
		// Don't crow about success when the trie is missing data
		// from a source — ops should investigate.
		r.mx.RefreshTotal.WithLabel("ok_partial").Add(1)
	} else {
		r.mx.RefreshTotal.WithLabel("ok").Add(1)
	}
	r.mx.RefreshAgeSeconds.SetNow(r.cfg.Now)
	return nil
}

func (r *Refresher) fetchSource(ctx context.Context, src Source) ([]*net.IPNet, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src.URL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "mcp-analytics-classifier/1 (+https://mcp-analytics.com/)")
	req.Header.Set("Accept", "application/json, text/plain")
	resp, err := r.cfg.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil, fmt.Errorf("%s: HTTP %d", src.Name, resp.StatusCode)
	}

	const maxBody = 32 * 1024 * 1024 // 32MB; AWS ip-ranges.json is ~5MB
	return ParseSource(src.Format, io.LimitReader(resp.Body, maxBody))
}

// Run blocks until ctx is cancelled, refreshing on Interval ticks.
// Uses time.NewTicker (not time.After) so the timer is properly disposed
// on shutdown.
func (r *Refresher) Run(ctx context.Context) {
	ticker := time.NewTicker(r.cfg.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := r.RunOnce(ctx); err != nil {
				r.cfg.Log.Warn("classify refresh failed", "err", err)
			} else {
				r.cfg.Log.Info("classify refresh ok",
					"loaded", r.mx.CIDRsLoaded.Total())
			}
		}
	}
}

// Bootstrap is the canonical startup sequence:
//
//  1. Build a Trie from FallbackRanges() and store it into target so
//     classification works immediately, even with no network.
//  2. Try one synchronous refresh with bootstrapTimeout. If it
//     succeeds, live data takes over. If it fails (network down,
//     endpoint flapping), keep the fallback; the background goroutine
//     retries on Interval.
//
// Use from cmd/ingest/main.go before starting the http.Server. The
// bootstrap refresh failing is NOT a fatal error — boot with the
// embedded fallback rather than block the ingest service.
func Bootstrap(ctx context.Context, target *AtomicLookup, mx *Metrics, log *slog.Logger, bootstrapTimeout time.Duration) {
	// Step 1: load embedded fallback synchronously.
	fb := FallbackRanges()
	target.Store(NewTrie(fb))
	mx.CIDRsLoaded.WithSource("fallback").Store(int64(len(fb)))

	// Step 2: try one live refresh with a tight timeout.
	if bootstrapTimeout <= 0 {
		bootstrapTimeout = 2 * time.Second
	}
	bootCtx, cancel := context.WithTimeout(ctx, bootstrapTimeout)
	defer cancel()

	r := NewRefresher(target, mx, RefreshConfig{
		HTTPTimeout: bootstrapTimeout,
		Log:         log,
	})
	if err := r.RunOnce(bootCtx); err != nil {
		log.Warn("classify bootstrap refresh failed; running on embedded fallback",
			"err", err, "fallback_entries", len(fb))
	} else {
		log.Info("classify bootstrap refresh ok")
	}
}
