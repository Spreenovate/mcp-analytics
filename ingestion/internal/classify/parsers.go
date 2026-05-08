package classify

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
)

// ParseSource decodes one source's JSON/text payload into a list of
// CIDR strings. Returns an error if the payload doesn't match the
// expected format — the refresh loop turns that into a parse-error
// counter increment and keeps the previous trie around.
func ParseSource(format string, body io.Reader) ([]*net.IPNet, error) {
	switch format {
	case "openai":
		return parseOpenAI(body)
	case "google":
		return parseGoogle(body)
	case "bing":
		return parseBing(body)
	case "aws":
		return parseAWS(body)
	case "gcp":
		return parseGCP(body)
	case "cloudflare":
		return parseCloudflare(body)
	default:
		return nil, fmt.Errorf("classify: unknown source format %q", format)
	}
}

// --- OpenAI ----------------------------------------------------------
// Schema (May 2026):
//   { "creationTime": "...", "prefixes": [
//       { "ipv4Prefix": "23.98.142.176/28" },
//       { "ipv6Prefix": "2603:1030:7:..." },
//       ...
//   ]}
type openaiPayload struct {
	Prefixes []struct {
		IPv4 string `json:"ipv4Prefix"`
		IPv6 string `json:"ipv6Prefix"`
	} `json:"prefixes"`
}

func parseOpenAI(body io.Reader) ([]*net.IPNet, error) {
	var p openaiPayload
	if err := json.NewDecoder(body).Decode(&p); err != nil {
		return nil, fmt.Errorf("openai decode: %w", err)
	}
	out := make([]*net.IPNet, 0, len(p.Prefixes))
	for _, e := range p.Prefixes {
		for _, raw := range []string{e.IPv4, e.IPv6} {
			if raw == "" {
				continue
			}
			if n, err := parseCIDR(raw); err == nil {
				out = append(out, n)
				if len(out) >= MaxEntriesPerSource {
					return out, nil
				}
			}
		}
	}
	return out, nil
}

// --- Google ----------------------------------------------------------
// Schema (May 2026):
//   { "creationTime": "...", "prefixes": [
//       { "ipv4Prefix": "..." }, { "ipv6Prefix": "..." }, ...
//   ]}
// Same shape as OpenAI's, but I keep the parser separate so a future
// schema split (e.g. Google adds a "purpose" field per prefix) only
// touches one parser.
func parseGoogle(body io.Reader) ([]*net.IPNet, error) {
	var p openaiPayload // identical shape today
	if err := json.NewDecoder(body).Decode(&p); err != nil {
		return nil, fmt.Errorf("google decode: %w", err)
	}
	out := make([]*net.IPNet, 0, len(p.Prefixes))
	for _, e := range p.Prefixes {
		for _, raw := range []string{e.IPv4, e.IPv6} {
			if raw == "" {
				continue
			}
			if n, err := parseCIDR(raw); err == nil {
				out = append(out, n)
				if len(out) >= MaxEntriesPerSource {
					return out, nil
				}
			}
		}
	}
	return out, nil
}

// --- Bing ------------------------------------------------------------
// Schema (May 2026): same OpenAI/Google shape.
func parseBing(body io.Reader) ([]*net.IPNet, error) {
	return parseOpenAI(body)
}

// --- AWS -------------------------------------------------------------
// Schema:
//   { "syncToken": "...", "createDate": "...",
//     "prefixes":  [ { "ip_prefix": "...", "region": "...", "service": "...", ... } ],
//     "ipv6_prefixes": [ { "ipv6_prefix": "...", ... } ]
//   }
type awsPayload struct {
	Prefixes []struct {
		IPPrefix string `json:"ip_prefix"`
	} `json:"prefixes"`
	IPv6Prefixes []struct {
		IPv6Prefix string `json:"ipv6_prefix"`
	} `json:"ipv6_prefixes"`
}

func parseAWS(body io.Reader) ([]*net.IPNet, error) {
	var p awsPayload
	if err := json.NewDecoder(body).Decode(&p); err != nil {
		return nil, fmt.Errorf("aws decode: %w", err)
	}
	out := make([]*net.IPNet, 0, len(p.Prefixes)+len(p.IPv6Prefixes))
	for _, e := range p.Prefixes {
		if n, err := parseCIDR(e.IPPrefix); err == nil {
			out = append(out, n)
			if len(out) >= MaxEntriesPerSource {
				return out, nil
			}
		}
	}
	for _, e := range p.IPv6Prefixes {
		if n, err := parseCIDR(e.IPv6Prefix); err == nil {
			out = append(out, n)
			if len(out) >= MaxEntriesPerSource {
				return out, nil
			}
		}
	}
	return out, nil
}

// --- GCP -------------------------------------------------------------
// Schema:
//   { "syncToken": "...", "creationTime": "...",
//     "prefixes": [ { "ipv4Prefix": "..." } | { "ipv6Prefix": "..." }, ... ]
//   }
// Same shape as OpenAI's.
func parseGCP(body io.Reader) ([]*net.IPNet, error) {
	return parseOpenAI(body)
}

// --- Cloudflare ------------------------------------------------------
// Two endpoints (ips-v4, ips-v6), each plain text, one CIDR per line.
//   1.2.3.0/24
//   5.6.7.0/24
//   ...
func parseCloudflare(body io.Reader) ([]*net.IPNet, error) {
	scanner := bufio.NewScanner(body)
	// Explicit small buffer (4 KB) — CIDR lines are at most ~50 bytes,
	// so anything longer indicates the endpoint returned an HTML error
	// page or got hijacked. Failing fast (with bufio.ErrTooLong) is
	// correct behavior here; the refresh-loop's MinShrinkRatio check
	// will then keep the previous good trie.
	scanner.Buffer(make([]byte, 4096), 4096)
	var out []*net.IPNet
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if n, err := parseCIDR(line); err == nil {
			out = append(out, n)
			if len(out) >= MaxEntriesPerSource {
				return out, nil
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("cloudflare scan: %w", err)
	}
	return out, nil
}

// MinIPv4Prefix is the smallest accepted IPv4 prefix length. Anything
// broader (smaller number) is rejected as a defense against vendor-JSON
// poisoning — a compromised endpoint pushing 0.0.0.0/0 would otherwise
// hijack classification of the entire IPv4 space until the next refresh
// (or forever, if combined with a swap that passes MinShrinkRatio).
//
// Real-world floor: AWS's broadest published prefix is /8 (e.g. 3.0.0.0/8),
// no other vendor publishes anything broader. /8 is the right floor.
const MinIPv4Prefix = 8

// MinIPv6Prefix follows the same logic for IPv6. Vendors publish /32 or
// narrower; nothing broader is legitimate.
const MinIPv6Prefix = 32

// MaxEntriesPerSource caps each source's contribution to defend against
// pathologically-large vendor JSONs (a 32MB body of repeated minimal
// entries decodes to ~1M structs and fills ~200MB heap on a single
// refresh). At 200k entries per source we stay well under what's
// realistic — AWS has ~6k prefixes today.
const MaxEntriesPerSource = 200_000

// parseCIDR is a wrapper around net.ParseCIDR that:
//   - accepts a bare IP and treats it as a /32 (v4) or /128 (v6)
//   - rejects prefixes broader than the per-family floor (defends
//     against vendor-compromise pushing 0.0.0.0/0 etc.)
//   - returns the IPNet only (we don't need the IP separately)
func parseCIDR(raw string) (*net.IPNet, error) {
	if !strings.Contains(raw, "/") {
		ip := net.ParseIP(raw)
		if ip == nil {
			return nil, fmt.Errorf("invalid ip: %s", raw)
		}
		bits := 32
		if ip.To4() == nil {
			bits = 128
		}
		_, n, err := net.ParseCIDR(fmt.Sprintf("%s/%d", raw, bits))
		return n, err
	}
	_, n, err := net.ParseCIDR(raw)
	if err != nil || n == nil {
		return n, err
	}
	ones, bits := n.Mask.Size()
	switch bits {
	case 32:
		if ones < MinIPv4Prefix {
			return nil, fmt.Errorf("ipv4 prefix /%d too broad (min /%d): %s",
				ones, MinIPv4Prefix, raw)
		}
	case 128:
		// Detect v4-mapped IPv6 prefixes (::ffff:0:0/96 family). These
		// LOOK like IPv6 (bits=128) but cidranger matches IPv4 lookup
		// keys against them — a hostile vendor JSON containing
		// {"ipv6Prefix":"::ffff:0.0.0.0/96"} would otherwise pass the
		// IPv6 floor (/96 >= /32) and hijack the entire IPv4 space.
		// Convert the v4-mapped prefix to its IPv4 equivalent and
		// re-validate against the IPv4 floor.
		if isV4MappedNet(n) {
			effectiveOnes := ones - 96
			if effectiveOnes < MinIPv4Prefix {
				return nil, fmt.Errorf(
					"v4-mapped ipv6 prefix /%d (effective ipv4 /%d) too broad (min /%d): %s",
					ones, effectiveOnes, MinIPv4Prefix, raw)
			}
		} else if ones < MinIPv6Prefix {
			return nil, fmt.Errorf("ipv6 prefix /%d too broad (min /%d): %s",
				ones, MinIPv6Prefix, raw)
		}
	default:
		return nil, fmt.Errorf("unexpected mask bits=%d in %s", bits, raw)
	}
	return n, nil
}

// isV4MappedNet reports whether the IPNet's address sits inside the
// IPv4-mapped IPv6 prefix ::ffff:0:0/96. Such prefixes match IPv4
// lookups in cidranger and must be treated as IPv4 for the prefix-
// length floor.
func isV4MappedNet(n *net.IPNet) bool {
	if n == nil || len(n.IP) != net.IPv6len {
		return false
	}
	// First 80 bits must be zero, next 16 bits must be 0xff.
	for i := 0; i < 10; i++ {
		if n.IP[i] != 0 {
			return false
		}
	}
	return n.IP[10] == 0xff && n.IP[11] == 0xff
}
