package ratelimit

import "testing"

func TestLimiter_AllowsUpToCapacity(t *testing.T) {
	l := New(5) // 5 tokens/sec capacity
	for i := 0; i < 5; i++ {
		if !l.Allow("siteA") {
			t.Fatalf("call %d unexpectedly rate-limited", i)
		}
	}
	if l.Allow("siteA") {
		t.Error("6th call should be rate-limited")
	}
}

func TestLimiter_KeysAreIndependent(t *testing.T) {
	l := New(2)
	for i := 0; i < 2; i++ {
		l.Allow("siteA")
	}
	if !l.Allow("siteB") {
		t.Error("siteB should not be affected by siteA's bucket")
	}
}

func TestLimiter_SweepRemovesIdleBuckets(t *testing.T) {
	l := New(1)
	l.Allow("temp")
	l.Sweep(0) // any positive age would remove; 0 means keep nothing-newer-than-now (= remove all)
	l.mu.Lock()
	n := len(l.buckets)
	l.mu.Unlock()
	if n != 0 {
		t.Errorf("expected sweep to remove buckets, got %d remaining", n)
	}
}
