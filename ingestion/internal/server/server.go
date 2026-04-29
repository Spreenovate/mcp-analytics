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
	"github.com/mcp-analytics/ingestion/internal/ipblock"
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
	IPBlock   *ipblock.Tracker // optional; nil disables the feature
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
	Site      string                 `json:"site"`
	Name      string                 `json:"name"`
	URL       string                 `json:"url"`
	Referrer  string                 `json:"referrer"`
	Props     map[string]interface{} `json:"props"`
	VisitorID string                 `json:"visitor_id,omitempty"` // only honored in mode=all
	// Stufe-2 client-side signals (all optional).
	Timezone          string `json:"tz,omitempty"`
	Language          string `json:"lang,omitempty"`
	ColorScheme       string `json:"cs,omitempty"`
	ViewportW         uint16 `json:"vw,omitempty"`
	ViewportH         uint16 `json:"vh,omitempty"`
	EngagementSeconds uint32 `json:"es,omitempty"` // engagement event only
	ScrollDepth       uint8  `json:"sd,omitempty"` // engagement event only
}

func (s *Server) handleEvent(w http.ResponseWriter, r *http.Request) {
	// CORS: the tracker runs under arbitrary origins and browsers sometimes
	// attach credentials (cookies) to sendBeacon requests. With credentials
	// we can't use `Access-Control-Allow-Origin: *` — echo the request's
	// Origin back instead (same practical effect as wildcard, without the
	// conflict). Vary ensures caches don't mix responses across origins.
	if origin := r.Header.Get("Origin"); origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
	}
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "content-type")
	w.Header().Set("Access-Control-Max-Age", "86400")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
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

	// Phase 1 bot classification: instead of dropping bot traffic, label it
	// and write the row anyway. Default analytics queries filter to
	// traffic_class='user'; the new top_user_agents MCP tool surfaces the
	// non-user traffic so customers can see who's visiting them.
	trafficClass := "user"
	if bot.IsBot(userAgent) {
		trafficClass = "bot"
	}

	ip := clientIP(r)

	if s.IPBlock != nil && s.IPBlock.IsBlocked(ip) {
		return
	}

	site, ok := s.Sites.Get(in.Site)
	if !ok {
		s.Usage.BumpUnknown(in.Site, time.Now())
		if s.IPBlock != nil {
			s.IPBlock.RecordUnknown(ip, in.Site)
		}
		return
	}

	if !s.Limiter.Allow(site.SiteID) {
		return
	}

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
	case "default":
		sessionID = session.DefaultSessionID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
		visitorID = session.DefaultVisitorID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
	case "all":
		// 'all' mode is the "I take the cookie-banner responsibility and want
		// real persistence" opt-in. No salt rotation applies; visitor_id is
		// the client's cookie id folded to UInt64. Site owner handles GDPR
		// consent — we give them maximum data retention in return.
		sessionID = session.DefaultSessionID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
		if isValidVisitorID(in.VisitorID) {
			// Fold the cookie id (UUID-ish string) into UInt64. No site_salt —
			// the cookie is already the source of truth for visitor identity.
			// Makes the mapping stable forever, regardless of any server-side
			// rotation we add later for other modes.
			visitorID = session.Compute([]byte(in.VisitorID))
		} else {
			// No cookie yet (DNT-blocked, private browsing with disabled storage,
			// or a customer that forgot data-persistent="true"). Fall back to
			// the IP+UA hash — not ideal for 'all' intent, but better than 0.
			visitorID = session.DefaultVisitorID([]byte(site.SiteSalt), ip, userAgent, site.SiteID)
		}
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
		TrafficClass:   trafficClass,
		UserAgent:      truncate(userAgent, 512),
		// Stufe-2 client signals. Truncate strings, clamp numbers.
		Timezone:          truncate(in.Timezone, 64),
		Language:          truncate(in.Language, 16),
		ColorScheme:       truncateColorScheme(in.ColorScheme),
		ViewportW:         clampU16(in.ViewportW, 8192),
		ViewportH:         clampU16(in.ViewportH, 8192),
		EngagementSeconds: clampU32(in.EngagementSeconds, 24*60*60), // cap at 1 day
		ScrollDepth:       clampU8(in.ScrollDepth, 100),
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

// isValidVisitorID accepts 16..64 chars of hex / base32 / dash. Anything
// weird gets ignored and we fall back to the server-computed hash, so a
// misbehaving client can't poison our analytics by sending garbage ids.
func isValidVisitorID(s string) bool {
	if len(s) < 16 || len(s) > 64 {
		return false
	}
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'z':
		case c >= 'A' && c <= 'Z':
		case c == '-':
		default:
			return false
		}
	}
	return true
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

// truncateColorScheme accepts only 'light' or 'dark'; anything else → ''.
// Locks the column to a tiny LowCardinality set so dimension queries stay fast.
func truncateColorScheme(s string) string {
	if s == "light" || s == "dark" {
		return s
	}
	return ""
}

func clampU16(v uint16, max uint16) uint16 {
	if v > max {
		return max
	}
	return v
}

func clampU32(v uint32, max uint32) uint32 {
	if v > max {
		return max
	}
	return v
}

func clampU8(v uint8, max uint8) uint8 {
	if v > max {
		return max
	}
	return v
}
