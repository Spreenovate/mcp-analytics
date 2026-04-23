package usage

import (
	"io"
	"log/slog"
	"testing"
	"time"
)

func newTestBuffer() *Buffer {
	return NewBuffer(nil, time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestBump_AccumulatesPerSiteAndMonth(t *testing.T) {
	b := newTestBuffer()

	at := time.Date(2026, 4, 23, 10, 0, 0, 0, time.UTC)
	b.Bump("siteA", at)
	b.Bump("siteA", at)
	b.Bump("siteB", at)

	// Different month, same site:
	b.Bump("siteA", at.AddDate(0, -1, 0))

	b.mu.Lock()
	defer b.mu.Unlock()

	if got := b.counters[key{SiteID: "siteA", Month: "2026-04-01"}]; got != 2 {
		t.Errorf("siteA April: want 2, got %d", got)
	}
	if got := b.counters[key{SiteID: "siteB", Month: "2026-04-01"}]; got != 1 {
		t.Errorf("siteB April: want 1, got %d", got)
	}
	if got := b.counters[key{SiteID: "siteA", Month: "2026-03-01"}]; got != 1 {
		t.Errorf("siteA March: want 1, got %d", got)
	}
}

func TestBumpUnknown_BucketsByHour(t *testing.T) {
	b := newTestBuffer()

	t1 := time.Date(2026, 4, 23, 10, 5, 0, 0, time.UTC)
	t2 := time.Date(2026, 4, 23, 10, 59, 0, 0, time.UTC) // same hour
	t3 := time.Date(2026, 4, 23, 11, 1, 0, 0, time.UTC)  // next hour

	b.BumpUnknown("ghost", t1)
	b.BumpUnknown("ghost", t2)
	b.BumpUnknown("ghost", t3)

	b.mu.Lock()
	defer b.mu.Unlock()

	if got := b.unknownCounters[unknownKey{SiteIDAttempted: "ghost", Hour: "2026-04-23 10:00:00"}]; got != 2 {
		t.Errorf("hour 10: want 2, got %d", got)
	}
	if got := b.unknownCounters[unknownKey{SiteIDAttempted: "ghost", Hour: "2026-04-23 11:00:00"}]; got != 1 {
		t.Errorf("hour 11: want 1, got %d", got)
	}
}

func TestMerge_PreservesPendingAfterFailedFlush(t *testing.T) {
	b := newTestBuffer()
	pending := map[key]int64{{SiteID: "x", Month: "2026-04-01"}: 7}
	unknown := map[unknownKey]int64{{SiteIDAttempted: "y", Hour: "2026-04-23 10:00:00"}: 4}

	b.merge(pending, unknown)

	b.mu.Lock()
	defer b.mu.Unlock()
	if b.counters[key{SiteID: "x", Month: "2026-04-01"}] != 7 {
		t.Errorf("merge lost pending counter")
	}
	if b.unknownCounters[unknownKey{SiteIDAttempted: "y", Hour: "2026-04-23 10:00:00"}] != 4 {
		t.Errorf("merge lost unknown counter")
	}
}
