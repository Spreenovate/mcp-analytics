// reclassify is a one-shot migration tool that walks the existing
// `events` table in ClickHouse and rewrites the traffic_class column
// using the Phase-2 8-class taxonomy.
//
// Phase 1 only emitted "user" or "bot". After Phase 2 ships, historic
// rows still carry the old value — this tool back-fills them by UA so
// charts immediately show the new taxonomy across the full retention
// window.
//
// Usage (against the production CH accessory via kamal):
//
//	zsh -ic 'kamal app exec --primary "go run ./cmd/reclassify"'
//
// Or locally against a dev CH:
//
//	CLICKHOUSE_URL=http://localhost:8123 \
//	CLICKHOUSE_USER=default CLICKHOUSE_PASSWORD= \
//	go run ./cmd/reclassify --apply
//
// Default mode is dry-run (prints what would change). Pass --apply to
// actually issue UPDATEs.
//
// IP-based reclassification is NOT performed: the `events` table
// deliberately does not store client IPs (privacy by design), so the
// only signal available retroactively is the UA. Rows that classify
// differently with IP+UA than UA-alone will continue to carry their
// original class until they age out — this is intentional.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/mcp-analytics/ingestion/internal/classify"
)

func main() {
	apply := flag.Bool("apply", false, "Actually issue UPDATE statements (default: dry-run)")
	chURL := flag.String("clickhouse-url", envOr("CLICKHOUSE_URL", "http://localhost:8123"), "ClickHouse HTTP endpoint")
	chUser := flag.String("clickhouse-user", envOr("CLICKHOUSE_USER", "default"), "")
	chPass := flag.String("clickhouse-password", envOr("CLICKHOUSE_PASSWORD", ""), "")
	chDB := flag.String("clickhouse-db", envOr("CLICKHOUSE_DB", "default"), "")
	flag.Parse()

	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	classifier := classify.NewClassifier(&classify.AtomicLookup{})

	cl := &chClient{
		baseURL:  *chURL,
		user:     *chUser,
		password: *chPass,
		db:       *chDB,
		http:     &http.Client{Timeout: 60 * time.Second},
	}

	ctx := context.Background()

	// Step 1: pull all distinct (user_agent, traffic_class) pairs from
	// the events table. We need both columns so we can skip rows that
	// already carry the right Phase-2 class — only rewrite where the
	// stored class differs from what the classifier wants.
	rows, err := cl.queryDistinctUAs(ctx)
	if err != nil {
		log.Error("query distinct UAs", "err", err)
		os.Exit(1)
	}
	log.Info("pulled UA list", "rows", len(rows))
	if len(rows) >= maxDistinctUAs {
		log.Warn("hit UA cap — long-tail UAs not reclassified this run",
			"cap", maxDistinctUAs,
			"hint", "if persistent, investigate UA-spam or move to streaming reclassify")
	}

	// Step 2: classify each UA with the Phase-2 logic (UA-only path,
	// no IP).
	type plan struct {
		ua       string
		oldClass string
		newClass string
	}
	var changes []plan
	skipped := 0
	for _, r := range rows {
		newClass := classifier.Classify(r.userAgent, nil)
		if newClass == r.oldClass {
			skipped++
			continue
		}
		changes = append(changes, plan{ua: r.userAgent, oldClass: r.oldClass, newClass: newClass})
	}
	log.Info("classification done",
		"changes", len(changes), "unchanged", skipped, "total", len(rows))

	// Step 3: emit UPDATE statements (or just print if --apply not set).
	for i, c := range changes {
		if !*apply {
			fmt.Printf("[dry-run %d/%d] %q  %s -> %s\n",
				i+1, len(changes), trim(c.ua, 80), c.oldClass, c.newClass)
			continue
		}
		if err := cl.updateTrafficClass(ctx, c.ua, c.oldClass, c.newClass); err != nil {
			log.Error("update failed",
				"ua", trim(c.ua, 80), "old", c.oldClass, "new", c.newClass, "err", err)
			continue
		}
		log.Info("updated",
			"ua", trim(c.ua, 80), "old", c.oldClass, "new", c.newClass, "i", i+1, "of", len(changes))
	}

	if !*apply {
		fmt.Printf("\n%d rows would be updated. Re-run with --apply to actually do it.\n",
			len(changes))
	}
}

// --- minimal CH HTTP client (avoid pulling the full app's ch package
// which is batched-insert-flavored, not query-flavored). ----

type chClient struct {
	baseURL, user, password, db string
	http                        *http.Client
}

type uaRow struct {
	userAgent string
	oldClass  string
}

func (c *chClient) query(ctx context.Context, sql string) (string, error) {
	q := url.Values{}
	q.Set("database", c.db)
	q.Set("query", sql)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.baseURL+"/?"+q.Encode(), nil)
	if err != nil {
		return "", err
	}
	if c.user != "" {
		req.SetBasicAuth(c.user, c.password)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("clickhouse %d: %s", resp.StatusCode, string(body))
	}
	return string(body), nil
}

// Hard ceiling on how many (UA, class) pairs we pull into memory in a
// single run. At 100k pairs * ~150 B average = ~15 MB, so OOM is not a
// concern up to that point. The auto-loop in entrypoint.sh re-runs
// every 24h, so a UA-spam attack that pushed beyond this would still
// see the most-frequent UAs reclassified each cycle — the long tail
// keeps its old class until volume drops or we move to streaming.
const maxDistinctUAs = 100_000

func (c *chClient) queryDistinctUAs(ctx context.Context) ([]uaRow, error) {
	// ORDER BY count() DESC: if we hit the cap, we want to have
	// reclassified the high-volume UAs first, not a random sample.
	out, err := c.query(ctx, fmt.Sprintf(`
		SELECT user_agent, traffic_class
		FROM events
		WHERE user_agent != ''
		GROUP BY user_agent, traffic_class
		ORDER BY count() DESC
		LIMIT %d
		FORMAT TabSeparated`, maxDistinctUAs))
	if err != nil {
		return nil, err
	}
	var rows []uaRow
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		rows = append(rows, uaRow{userAgent: parts[0], oldClass: parts[1]})
	}
	return rows, nil
}

func (c *chClient) updateTrafficClass(ctx context.Context, ua, oldClass, newClass string) error {
	// Use parameter binding to avoid SQL injection — CH supports {x:Type}
	// placeholders via param_<name> URL params with the
	// `param_<name>` mechanism.
	q := url.Values{}
	q.Set("database", c.db)
	q.Set("param_ua", ua)
	q.Set("param_old", oldClass)
	q.Set("param_new", newClass)
	// mutations_sync=1: wait for the mutation to finish on this replica
	// before returning. Default is 0 (queue-and-return) which lets the
	// async mutation queue stack up if the auto-loop runs faster than
	// CH can rewrite parts. We're on a single CH instance so =1
	// suffices; bump to 2 if we ever go multi-replica.
	q.Set("mutations_sync", "1")
	q.Set("query", `
		ALTER TABLE events
		UPDATE traffic_class = {new:String}
		WHERE user_agent = {ua:String} AND traffic_class = {old:String}`)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.baseURL+"/?"+q.Encode(), nil)
	if err != nil {
		return err
	}
	if c.user != "" {
		req.SetBasicAuth(c.user, c.password)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("clickhouse %d: %s", resp.StatusCode, string(body))
	}
	return nil
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func trim(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
