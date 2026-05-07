//go:build livesources
// +build livesources

// Live-source schema check. Excluded from default CI (would make tests
// flaky against external endpoints) and only run by the dedicated
// .github/workflows/ai-crawler-schema-check.yml workflow on a daily
// cron.
//
// What it asserts: every Source in classify.Sources() responds 200,
// is parseable by the right parser, and yields at least one valid
// CIDR. Anything else means a vendor changed their schema (or the URL)
// and we need to update the parser/source list.

package classify

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"
)

func TestLiveSources(t *testing.T) {
	timeout := 10 * time.Second
	if v := os.Getenv("MCP_LIVE_FETCH_TIMEOUT"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			timeout = d
		}
	}
	httpClient := &http.Client{Timeout: timeout}

	for _, src := range Sources() {
		src := src
		t.Run(src.Name, func(t *testing.T) {
			t.Parallel()
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()

			req, err := http.NewRequestWithContext(ctx, http.MethodGet, src.URL, nil)
			if err != nil {
				t.Fatalf("new request: %v", err)
			}
			req.Header.Set("User-Agent", "mcp-analytics-schema-check/1 (CI)")
			req.Header.Set("Accept", "application/json, text/plain")
			resp, err := httpClient.Do(req)
			if err != nil {
				t.Fatalf("fetch %s: %v", src.URL, err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Fatalf("%s: HTTP %d (was %d) — endpoint may have moved",
					src.URL, resp.StatusCode, http.StatusOK)
			}

			nets, err := ParseSource(src.Format, resp.Body)
			if err != nil {
				t.Fatalf("parse %s (%s): %v — schema may have changed",
					src.Name, src.Format, err)
			}
			if len(nets) == 0 {
				t.Fatalf("%s: parsed 0 CIDRs — empty payload or schema mismatch",
					src.Name)
			}
			t.Logf("%s ok: %d CIDRs", src.Name, len(nets))
		})
	}
}
