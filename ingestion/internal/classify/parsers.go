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
		}
	}
	for _, e := range p.IPv6Prefixes {
		if n, err := parseCIDR(e.IPv6Prefix); err == nil {
			out = append(out, n)
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
	var out []*net.IPNet
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if n, err := parseCIDR(line); err == nil {
			out = append(out, n)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("cloudflare scan: %w", err)
	}
	return out, nil
}

// parseCIDR is a forgiving wrapper around net.ParseCIDR that:
//   - accepts a bare IP and treats it as a /32 (v4) or /128 (v6)
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
	return n, err
}
