package ratelimit

import (
	"sync"
	"time"
)

// Limiter implements a simple per-key token bucket.
// Used per site_id at ingest time to protect against runaway traffic.
type Limiter struct {
	ratePerSec int
	mu         sync.Mutex
	buckets    map[string]*bucket
}

type bucket struct {
	tokens     float64
	lastRefill time.Time
}

func New(ratePerSec int) *Limiter {
	return &Limiter{
		ratePerSec: ratePerSec,
		buckets:    make(map[string]*bucket, 64),
	}
}

func (l *Limiter) Allow(key string) bool {
	now := time.Now()
	max := float64(l.ratePerSec)

	l.mu.Lock()
	defer l.mu.Unlock()

	b, ok := l.buckets[key]
	if !ok {
		l.buckets[key] = &bucket{tokens: max - 1, lastRefill: now}
		return true
	}

	elapsed := now.Sub(b.lastRefill).Seconds()
	if elapsed > 0 {
		b.tokens = minFloat(max, b.tokens+elapsed*float64(l.ratePerSec))
		b.lastRefill = now
	}
	if b.tokens >= 1 {
		b.tokens--
		return true
	}
	return false
}

// Sweep removes buckets that haven't been touched recently to keep memory bounded.
func (l *Limiter) Sweep(olderThan time.Duration) {
	cutoff := time.Now().Add(-olderThan)
	l.mu.Lock()
	defer l.mu.Unlock()
	for k, b := range l.buckets {
		if b.lastRefill.Before(cutoff) {
			delete(l.buckets, k)
		}
	}
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
