package server

import (
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"time"

	"github.com/mcp-analytics/ingestion/internal/bot"
	"github.com/mcp-analytics/ingestion/internal/ch"
	"github.com/mcp-analytics/ingestion/internal/ratelimit"
	"github.com/mcp-analytics/ingestion/internal/session"
	"github.com/mcp-analytics/ingestion/internal/sites"
	"github.com/mcp-analytics/ingestion/internal/ua"
	"github.com/mcp-analytics/ingestion/internal/usage"
)

const maxPayloadBytes = 16 * 1024

type Server struct {
	Log       *slog.Logger
	Sites     *sites.Cache
	Batcher   *ch.Batcher
	Usage     *usage.Buffer
	DailySalt *session.DailySalt
	Limiter   *ratelimit.Limiter
	StaticDir string
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/event", s.handleEvent)
	mux.HandleFunc("/script.js", s.handleScript)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	return mux
}

type eventIn struct {
	Site     string                 `json:"site"`
	Name     string                 `json:"name"`
	URL      string                 `json:"url"`
	Referrer string                 `json:"referrer"`
	Props    map[string]interface{} `json:"props"`
}

func (s *Server) handleEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	// Always respond 204 — we never surface ingest errors to the client so that
	// unknown-site tracking fails silently (see briefing).
	defer w.WriteHeader(http.StatusNoContent)

	body, err := io.ReadAll(io.LimitReader(r.Body, maxPayloadBytes))
	if err != nil {
		return
	}
	var in eventIn
	if err := json.Unmarshal(body, &in); err != nil {
		return
	}
	if in.Site == "" {
		return
	}

	userAgent := r.Header.Get("User-Agent")
	if bot.IsBot(userAgent) {
		return
	}

	site, ok := s.Sites.Get(in.Site)
	if !ok {
		s.Usage.BumpUnknown(in.Site, time.Now())
		return
	}

	if !s.Limiter.Allow(site.SiteID) {
		return
	}

	ip := clientIP(r)

	name := in.Name
	if name == "" {
		name = "pageview"
	}

	parsedURL, _ := url.Parse(in.URL)
	parsedRef, _ := url.Parse(in.Referrer)

	var sessionID, visitorID uint64
	switch site.PrivacyMode {
	case "strict":
		sessionID = session.StrictSessionID(
			s.DailySalt.Current(), []byte(site.SiteSalt), ip, userAgent, site.SiteID)
		visitorID = 0
	case "default", "all":
		// 'all' differs from 'default' in cookie-backed persistence, which is
		// a tracker-side concern; server-side we treat it like 'default' for
		// MVP (persistent hash over site_salt lifetime).
		sessionID = session.DefaultSessionID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
		visitorID = session.DefaultVisitorID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
	default:
		sessionID = session.StrictSessionID(
			s.DailySalt.Current(), []byte(site.SiteSalt), ip, userAgent, site.SiteID)
	}

	uap := ua.Parse(userAgent)

	var urlHost, urlPath string
	if parsedURL != nil {
		urlHost = parsedURL.Host
		urlPath = parsedURL.Path
	}

	var refHost, refPath string
	if parsedRef != nil && parsedRef.Host != parsedURL.Host {
		refHost = parsedRef.Host
		if site.PrivacyMode != "strict" {
			refPath = parsedRef.Path
		}
	}

	utmSource, utmMedium, utmCampaign := extractUTM(parsedURL)

	propKeys, propValues := flattenProps(in.Props)

	ev := ch.Event{
		SiteID:         site.SiteID,
		Timestamp:      time.Now().UTC().Format("2006-01-02 15:04:05.000"),
		EventName:      truncate(name, 64),
		SessionID:      sessionID,
		VisitorID:      visitorID,
		URLPath:        truncate(urlPath, 2048),
		URLHost:        truncate(urlHost, 253),
		ReferrerHost:   truncate(refHost, 253),
		ReferrerPath:   truncate(refPath, 2048),
		UTMSource:      truncate(utmSource, 128),
		UTMMedium:      truncate(utmMedium, 128),
		UTMCampaign:    truncate(utmCampaign, 128),
		Browser:        uap.Browser,
		BrowserVersion: uap.BrowserVersion,
		OS:             uap.OS,
		DeviceType:     uap.DeviceType,
		PropKeys:       propKeys,
		PropValues:     propValues,
	}

	s.Batcher.Submit(ev)
	s.Usage.Bump(site.SiteID, time.Now())
}

func (s *Server) handleScript(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeFile(w, r, filepath.Join(s.StaticDir, "script.js"))
}

func clientIP(r *http.Request) string {
	// kamal-proxy forwards the client IP in X-Forwarded-For. Take the first hop.
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.Index(xff, ","); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func extractUTM(u *url.URL) (string, string, string) {
	if u == nil {
		return "", "", ""
	}
	q := u.Query()
	return q.Get("utm_source"), q.Get("utm_medium"), q.Get("utm_campaign")
}

func flattenProps(props map[string]interface{}) ([]string, []string) {
	if len(props) == 0 {
		return nil, nil
	}
	// Cap keys to 20 (tracker already does this, defense-in-depth here).
	if len(props) > 20 {
		out := make(map[string]interface{}, 20)
		n := 0
		for k, v := range props {
			out[k] = v
			n++
			if n >= 20 {
				break
			}
		}
		props = out
	}

	keys := make([]string, 0, len(props))
	vals := make([]string, 0, len(props))
	for k, v := range props {
		keys = append(keys, truncate(k, 128))
		vals = append(vals, truncate(stringifyProp(v), 1024))
	}
	return keys, vals
}

func stringifyProp(v interface{}) string {
	switch x := v.(type) {
	case string:
		return x
	case bool:
		if x {
			return "true"
		}
		return "false"
	case float64:
		b, _ := json.Marshal(x)
		return string(b)
	case nil:
		return ""
	default:
		b, _ := json.Marshal(x)
		return string(b)
	}
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}
