package server

import (
	"net/http/httptest"
	"testing"
)

// XFF parsing — must take the RIGHTMOST entry (kamal-proxy's append),
// not the leftmost (which is attacker-controlled). This test would
// have failed in Phase 1 where clientIP took the first entry.

func TestClientIP_RightmostXFFEntry(t *testing.T) {
	cases := []struct {
		name string
		xff  string
		want string
	}{
		{
			name: "single entry returned as-is",
			xff:  "203.0.113.5",
			want: "203.0.113.5",
		},
		{
			name: "two entries: take rightmost (proxy's append)",
			xff:  "23.98.142.180, 203.0.113.5",
			want: "203.0.113.5",
		},
		{
			name: "attacker spoofs OpenAI IP at the front, real IP at end",
			xff:  "23.98.142.180, 198.51.100.99, 203.0.113.5",
			want: "203.0.113.5",
		},
		{
			name: "trailing whitespace tolerated",
			xff:  "1.2.3.4 ,  5.6.7.8",
			want: "5.6.7.8",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/event", nil)
			req.Header.Set("X-Forwarded-For", c.xff)
			got := clientIP(req)
			if got != c.want {
				t.Errorf("XFF=%q: got %q want %q", c.xff, got, c.want)
			}
		})
	}
}

func TestClientIP_FallsBackToRemoteAddr(t *testing.T) {
	req := httptest.NewRequest("POST", "/event", nil)
	req.RemoteAddr = "203.0.113.5:54321"
	if got := clientIP(req); got != "203.0.113.5" {
		t.Errorf("got %q want %q", got, "203.0.113.5")
	}
}
