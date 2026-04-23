package session

import (
	"bytes"
	"testing"
)

func TestStrictSessionID_DeterministicForSameInputs(t *testing.T) {
	salt1 := []byte("daily-salt-A")
	salt2 := []byte("site-salt-B")
	id1 := StrictSessionID(salt1, salt2, "1.2.3.4", "Mozilla/5.0", "site_xyz")
	id2 := StrictSessionID(salt1, salt2, "1.2.3.4", "Mozilla/5.0", "site_xyz")
	if id1 != id2 {
		t.Fatalf("expected deterministic id, got %d != %d", id1, id2)
	}
}

func TestStrictSessionID_ChangesWithDailySalt(t *testing.T) {
	siteSalt := []byte("site")
	id1 := StrictSessionID([]byte("salt-day-1"), siteSalt, "1.2.3.4", "ua", "site")
	id2 := StrictSessionID([]byte("salt-day-2"), siteSalt, "1.2.3.4", "ua", "site")
	if id1 == id2 {
		t.Error("session id must rotate with daily salt")
	}
}

func TestDefaultSessionAndVisitor_AreDistinct(t *testing.T) {
	siteSalt := []byte("site-salt")
	sess := DefaultSessionID(siteSalt, "1.2.3.4", "ua", "site")
	visit := DefaultVisitorID(siteSalt, "1.2.3.4", "ua", "site")
	if sess == visit {
		t.Error("session and visitor IDs must differ for same inputs")
	}
}

func TestDailySalt_RotatesValueOnNewSeed(t *testing.T) {
	calls := 0
	seedFn := func() []byte {
		calls++
		return []byte{byte(calls)}
	}
	s := NewDailySalt(seedFn)
	first := s.Current()
	if !bytes.Equal(first, []byte{1}) {
		t.Fatalf("expected first salt to come from seedFn call 1, got %v", first)
	}
	// Same UTC day: no extra rotation, same value.
	again := s.Current()
	if !bytes.Equal(again, first) {
		t.Error("salt should not change within the same UTC day")
	}
	if calls != 1 {
		t.Errorf("seedFn called %d times, want 1", calls)
	}
}

func TestCompute_ProducesNonZeroForNonEmpty(t *testing.T) {
	if Compute([]byte("hello")) == 0 {
		t.Error("Compute should not return 0 for normal inputs")
	}
}
