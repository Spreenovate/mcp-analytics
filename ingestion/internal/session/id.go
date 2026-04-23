package session

import (
	"crypto/sha256"
	"encoding/binary"
	"sync"
	"time"
)

// DailySalt rotates once per UTC day. Callers fetch the current salt; the
// previous day's salt is forgotten, which is the whole point of strict mode.
type DailySalt struct {
	mu      sync.RWMutex
	date    string
	value   []byte
	seedFn  func() []byte
}

func NewDailySalt(seedFn func() []byte) *DailySalt {
	s := &DailySalt{seedFn: seedFn}
	s.rotate(time.Now().UTC())
	return s
}

// Current returns the salt for today, rotating if the UTC date changed.
func (s *DailySalt) Current() []byte {
	today := time.Now().UTC().Format("2006-01-02")

	s.mu.RLock()
	if s.date == today {
		v := s.value
		s.mu.RUnlock()
		return v
	}
	s.mu.RUnlock()

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.date != today {
		s.rotate(time.Now().UTC())
	}
	return s.value
}

func (s *DailySalt) rotate(now time.Time) {
	s.date = now.Format("2006-01-02")
	s.value = s.seedFn()
}

// Compute returns a UInt64 id from hashing the given inputs with SHA-256
// and taking the first 8 bytes. Used for both session_id and visitor_id.
func Compute(parts ...[]byte) uint64 {
	h := sha256.New()
	for _, p := range parts {
		h.Write(p)
	}
	sum := h.Sum(nil)
	return binary.BigEndian.Uint64(sum[:8])
}

// Strict: session_id = H(daily_salt | site_salt | ip | ua | site_id); visitor_id = 0.
// Default: session_id = H(site_salt | ip | ua | site_id | "session");
//          visitor_id = H(site_salt | ip | ua | site_id | "visitor").
// (The separate "session"/"visitor" suffixes keep them distinct under the same salt.)
func StrictSessionID(dailySalt, siteSalt []byte, ip, ua, siteID string) uint64 {
	return Compute(dailySalt, siteSalt, []byte(ip), []byte(ua), []byte(siteID))
}

func DefaultSessionID(siteSalt []byte, ip, ua, siteID string) uint64 {
	return Compute(siteSalt, []byte(ip), []byte(ua), []byte(siteID), []byte("|session"))
}

func DefaultVisitorID(siteSalt []byte, ip, ua, siteID string) uint64 {
	return Compute(siteSalt, []byte(ip), []byte(ua), []byte(siteID), []byte("|visitor"))
}
