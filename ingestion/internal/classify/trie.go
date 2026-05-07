package classify

import (
	"net"
	"sync/atomic"

	"github.com/yl2chen/cidranger"
)

// IPLookup is the read-only interface the hot path needs. Implemented
// by *Trie below and stub-able in tests.
type IPLookup interface {
	// Lookup returns the most specific match for ip and a boolean
	// indicating whether anything matched. The returned Class is the
	// classification we'd assign based on IP alone (heuristic.go may
	// override this).
	Lookup(ip net.IP) (Class, string, bool)
}

// Trie wraps cidranger to expose Class+Provider per CIDR. cidranger is
// allocation-light on lookup (it walks an internal radix structure),
// so we stay well under the 0.1ms hot-path budget even with ~100k
// entries.
type Trie struct {
	r cidranger.Ranger
}

// taggedNet implements cidranger.RangerEntry and carries the
// per-CIDR classification metadata.
type taggedNet struct {
	net      net.IPNet
	class    Class
	provider string
	cloud    bool
}

func (t *taggedNet) Network() net.IPNet { return t.net }

// NewTrie builds a Trie from the given entries. The slice is consumed
// up-front; subsequent updates require building a new Trie and
// atomic-swapping it in (see classifier.go).
func NewTrie(entries []TrieEntry) *Trie {
	r := cidranger.NewPCTrieRanger()
	for _, e := range entries {
		// Deliberately ignore Insert errors — they're either for
		// invalid CIDRs (already filtered in parsers) or duplicate
		// entries (harmless overlap).
		_ = r.Insert(&taggedNet{
			net:      *e.Net,
			class:    e.Class,
			provider: e.Provider,
			cloud:    e.IsCloudInfra,
		})
	}
	return &Trie{r: r}
}

// TrieEntry is the input shape for NewTrie. Sources(), parsers, and
// fallbacks all produce []TrieEntry which gets handed to NewTrie.
type TrieEntry struct {
	Net          *net.IPNet
	Class        Class
	Provider     string
	IsCloudInfra bool
}

// Lookup returns the most specific covering CIDR for the given IP. If
// multiple CIDRs match, the most specific (highest-prefix) one wins
// because cidranger returns them in decreasing specificity order. We
// deliberately prefer NON-cloud-infra matches over cloud ones at the
// same depth: a /24 inside a /16 cloud range that's also tagged as
// gptbot should classify as ai_training, not aws.
func (t *Trie) Lookup(ip net.IP) (Class, string, bool) {
	if t == nil || t.r == nil || ip == nil {
		return "", "", false
	}
	matches, err := t.r.ContainingNetworks(ip)
	if err != nil || len(matches) == 0 {
		return "", "", false
	}

	// First pass: prefer specific (non-cloud-infra) matches. cidranger
	// returns from least- to most-specific, so iterate in reverse.
	var fallback *taggedNet
	for i := len(matches) - 1; i >= 0; i-- {
		tn, ok := matches[i].(*taggedNet)
		if !ok {
			continue
		}
		if !tn.cloud {
			return tn.class, tn.provider, true
		}
		if fallback == nil {
			fallback = tn
		}
	}
	if fallback != nil {
		return fallback.class, fallback.provider, true
	}
	return "", "", false
}

// IsCloud reports whether the IP falls within any cloud-infra range.
// Used by the heuristic layer (cloud-IP + generic-Chrome → scanner).
// Doesn't itself classify — just answers "is this from a known cloud
// provider".
func (t *Trie) IsCloud(ip net.IP) bool {
	if t == nil || t.r == nil || ip == nil {
		return false
	}
	matches, err := t.r.ContainingNetworks(ip)
	if err != nil {
		return false
	}
	for _, m := range matches {
		if tn, ok := m.(*taggedNet); ok && tn.cloud {
			return true
		}
	}
	return false
}

// EmptyLookup is a Lookup implementation that never matches. Used as
// the bootstrap value before the first refresh completes — the
// classifier still works, just without IP enrichment.
type EmptyLookup struct{}

func (EmptyLookup) Lookup(_ net.IP) (Class, string, bool) { return "", "", false }
func (EmptyLookup) IsCloud(_ net.IP) bool                 { return false }

// AtomicLookup wraps an IPLookup behind atomic.Pointer so the refresh
// goroutine can swap in a new trie without locking the hot path.
type AtomicLookup struct {
	cur atomic.Pointer[Trie]
}

func (a *AtomicLookup) Store(t *Trie) { a.cur.Store(t) }

func (a *AtomicLookup) Lookup(ip net.IP) (Class, string, bool) {
	t := a.cur.Load()
	if t == nil {
		return "", "", false
	}
	return t.Lookup(ip)
}

func (a *AtomicLookup) IsCloud(ip net.IP) bool {
	t := a.cur.Load()
	if t == nil {
		return false
	}
	return t.IsCloud(ip)
}
