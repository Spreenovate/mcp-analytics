package ipblock

import (
	"sync/atomic"
	"testing"
	"time"
)

// fakeClock lets the tests drive `Now` deterministically.
type fakeClock struct {
	t atomic.Int64 // unix nanos
}

func (c *fakeClock) now() time.Time { return time.Unix(0, c.t.Load()) }
func (c *fakeClock) set(t time.Time) { c.t.Store(t.UnixNano()) }
func (c *fakeClock) advance(d time.Duration) {
	c.t.Store(c.t.Load() + int64(d))
}

func TestRecordUnknown_BelowThresholdDoesNotBlock(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	tr := New(Options{Threshold: 3, Window: time.Hour, BlockFor: time.Hour, Now: clk.now})

	tr.RecordUnknown("1.1.1.1", "a")
	tr.RecordUnknown("1.1.1.1", "b")
	tr.RecordUnknown("1.1.1.1", "c")

	if tr.IsBlocked("1.1.1.1") {
		t.Fatal("at threshold should still not be blocked (> threshold blocks)")
	}
}

func TestRecordUnknown_AboveThresholdBlocksAndFiresOnce(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	var fires atomic.Int32
	tr := New(Options{
		Threshold: 3, Window: time.Hour, BlockFor: time.Hour,
		Now: clk.now,
		OnBlock: func(ip string, uniq int, _ time.Time) {
			fires.Add(1)
			if ip != "2.2.2.2" {
				t.Errorf("unexpected ip: %q", ip)
			}
			if uniq < 4 {
				t.Errorf("expected at least 4 unique sites, got %d", uniq)
			}
		},
	})

	for _, s := range []string{"a", "b", "c", "d"} {
		tr.RecordUnknown("2.2.2.2", s)
	}
	if !tr.IsBlocked("2.2.2.2") {
		t.Fatal("should be blocked after crossing threshold")
	}
	if fires.Load() != 1 {
		t.Fatalf("OnBlock fired %d times, want 1", fires.Load())
	}

	// Further records during the same block must NOT re-fire.
	tr.RecordUnknown("2.2.2.2", "e")
	tr.RecordUnknown("2.2.2.2", "f")
	if fires.Load() != 1 {
		t.Fatalf("OnBlock re-fired during block, got %d", fires.Load())
	}
}

func TestRecordUnknown_DedupSameSiteIDDoesNotCountTwice(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	tr := New(Options{Threshold: 3, Window: time.Hour, BlockFor: time.Hour, Now: clk.now})

	for i := 0; i < 10; i++ {
		tr.RecordUnknown("3.3.3.3", "same-id")
	}
	if tr.IsBlocked("3.3.3.3") {
		t.Error("hitting the same site_id 10x should not block")
	}
}

func TestWindow_OldEntriesExpire(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	tr := New(Options{Threshold: 3, Window: time.Minute, BlockFor: time.Hour, Now: clk.now})

	tr.RecordUnknown("4.4.4.4", "a")
	tr.RecordUnknown("4.4.4.4", "b")
	tr.RecordUnknown("4.4.4.4", "c")

	// Advance past the window so the earlier three expire.
	clk.advance(2 * time.Minute)

	tr.RecordUnknown("4.4.4.4", "d")
	tr.RecordUnknown("4.4.4.4", "e")
	if tr.IsBlocked("4.4.4.4") {
		t.Error("fresh entries alone should not cross threshold")
	}
}

func TestBlock_ExpiresAfterBlockFor(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	tr := New(Options{Threshold: 2, Window: time.Hour, BlockFor: time.Minute, Now: clk.now})

	for _, s := range []string{"a", "b", "c"} {
		tr.RecordUnknown("5.5.5.5", s)
	}
	if !tr.IsBlocked("5.5.5.5") {
		t.Fatal("should be blocked initially")
	}

	clk.advance(2 * time.Minute)
	if tr.IsBlocked("5.5.5.5") {
		t.Error("block should have expired")
	}
}

func TestIsBlocked_UnknownIP(t *testing.T) {
	tr := New(Options{Threshold: 3})
	if tr.IsBlocked("99.99.99.99") {
		t.Error("unknown ip must not be blocked")
	}
}

func TestSweep_DropsIdleIPs_KeepsBlocked(t *testing.T) {
	clk := &fakeClock{}
	clk.set(time.Unix(1_700_000_000, 0))
	tr := New(Options{Threshold: 2, Window: time.Minute, BlockFor: time.Hour, Now: clk.now})

	// Idle IP — will become stale.
	tr.RecordUnknown("idle", "x")
	// Blocked IP — must be kept.
	for _, s := range []string{"a", "b", "c"} {
		tr.RecordUnknown("blocked", s)
	}

	clk.advance(2 * time.Minute)
	tr.Sweep()

	tr.mu.Lock()
	_, hasIdle := tr.entries["idle"]
	_, hasBlocked := tr.entries["blocked"]
	tr.mu.Unlock()

	if hasIdle {
		t.Error("idle entry should be swept")
	}
	if !hasBlocked {
		t.Error("blocked entry must be retained")
	}
}

func TestRecordUnknown_EmptyInputsNoop(t *testing.T) {
	tr := New(Options{Threshold: 1})
	tr.RecordUnknown("", "x")
	tr.RecordUnknown("ip", "")
	if tr.IsBlocked("") {
		t.Error("empty ip must not be blocked")
	}
}
