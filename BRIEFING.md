# PROJEKT: mcp-analytics — Working Document

Stand: 2026-05-07 · Branch: `main` · **Live in Production** seit Mai 2026
auf Hetzner CX32 Falkenstein (`49.13.165.191`).

Dieses Dokument ist der ursprüngliche Briefing-Text, annotiert mit dem
aktuellen Umsetzungsstand. Status-Tabelle reflektiert echten Code-Stand.

Legende: `[DONE]` umgesetzt · `[PARTIAL]` teilweise · `[TODO]` offen ·
`[SKIP]` bewusst nicht im MVP.

---

## STATUS-DASHBOARD

| Bereich                              | Status       | Hinweis                                                          |
|--------------------------------------|--------------|------------------------------------------------------------------|
| Deployment auf Hetzner CX32          | `[DONE]`     | Live seit Mai 2026, Kamal-Deploys laufen (zsh-wrapper-Trick siehe CLAUDE.md) |
| Rails-App Gerüst (Rails 8 + SQLite)  | `[DONE]`     | Gemfile, Dockerfile, config, routes, Solid Queue in Puma         |
| Datenmodell Rails                    | `[DONE]`     | Alle Migrations + Models inkl. OAuth-Tabellen vorhanden          |
| Datenmodell ClickHouse               | `[DONE]`     | `events` + `events_hourly` + `referrers_daily` MVs + `engagement_signals` |
| Go-Ingestion-Service                 | `[DONE]`     | Bot-Filter, Rate-Limit, Salt-Hashing, Usage-Buffer, Site-Cache, IP-Block |
| Tracking-Script                      | `[DONE]`     | `ingestion/static/script.js` (131 Zeilen)                        |
| MCP-Server + 18 Tools                | `[DONE]`     | JSON-RPC in `app/services/mcp/`                                  |
| OAuth 2.1 (Phase 2 + Hardening)      | `[DONE]`     | PKCE, DCR, RFC 8707, Two-Scope, Revocation (RFC 7009), Audit-Log, /settings-UI |
| Bot-Klassifikation Phase 1           | `[DONE]`     | `traffic_class` + `user_agent` Spalten, `top_user_agents` + `traffic_class_breakdown` MCP-Tools |
| Web-UI (Landing, Verify, Settings, Pricing) | `[DONE]` | Brutalist, Pricing-Section live (siehe `app/views/pages/home.html.erb`) |
| Signup-/Verify-Flow inkl. Mails      | `[DONE]`     | VerificationMailer, OAuth-Consent-Flow                           |
| Recurring Jobs (Salt, Purge, Usage)  | `[DONE]`     | `config/recurring.yml` + Job-Klassen inkl. OAuth-Audit-Prune     |
| Anti-Abuse (Rate-Limits)             | `[DONE]`     | /event, MCP 60/min, `register_account` 3/IP/h + 10/IP/d + 5/Dom/d, `magic_link`, alle OAuth-Endpoints |
| Anti-Abuse (Garbage-Site-IP-Block)   | `[DONE]`     | Go `ipblock` + Rails `AbuseAlertJob` (5-Min-Digest)              |
| Concurrency (Atomic UPSERTs)         | `[DONE]`     | `UsageCounter`, `UnknownSiteHit`                                 |
| Backup-Script                        | `[DONE]`     | `ops/backup.sh` (täglich, SQLite + ClickHouse)                   |
| Tests (88 Rails + 41 Go)             | `[DONE]`     | Models, MCP Tools/Controller, Verify, Sessions, Settings, OAuth full-flow |
| Pricing-Strategie + Landing-Section  | `[DONE]`     | 3-Tier-Modell finalisiert in `PRICING.md`, Landing-Page-Section live |
| Email-Blacklist für Trash-Domains    | `[PARTIAL]`  | Logik in `Tools#disposable_email_domain?` — Liste gegen aktuelle GitHub-Liste pflegen |
| Monitoring / Alerts                  | `[PARTIAL]`  | Usage-Alert + Garbage-Pattern done; Uptime/Disk-Alert noch offen |
| CI-Workflow                          | `[TODO]`     | `.github/workflows/` hat nur dependabot.yml; 129 Tests warten auf re-enable |
| Pricing-Implementation (Stripe etc.) | `[TODO]`     | `subscriptions`-Modell, Tier-Enforcement, Hard-Cap, Stripe/Lemon-Squeezy — siehe PRICING.md §9 |
| Bot-Phase 2 (Cloudflare-Taxonomie)   | `[DONE]`     | `internal/classify`: 8 Klassen + UA-Patterns + IP-CIDR-Trie (refresh 6h) + FCrDNS für Anthropic + Generic-Cloud-Heuristik |
| Bot-Phase 4 (Server-Side Ingestion)  | `[TODO]`     | Ruby-Gem + Node-Middleware + Pixel — Pro-Tier-Feature           |
| Dogfooding (retreaturlaub, triageflow)| `[TODO]`    | Tracker einbauen, eigene Daten via Claude abfragen               |

**Aktuelle Phase**: Production läuft, OAuth komplett, Pricing-Strategie steht.
Nächster Critical Path: Pricing-Implementation (Tier-Enforcement + Stripe) +
CI re-enable + Bot-Phase-2/4 als Pro-Tier-Features.

---

## ZIEL

Web-Analytics-Tool, das ausschließlich über das Model Context Protocol (MCP)
bedient wird – kein Dashboard, keine UI für die Analytics selbst. Nutzer
greifen via Claude/ChatGPT/anderer MCP-Clients auf ihre Analytics-Daten zu.
Erste Version: MVP zum Validieren der Idee, kostenlos bis 100k Hits/Monat,
keine Bezahlfunktion, keine Enterprise-Features.

## POSITIONIERUNG

"Analytics für deinen AI-Workflow. Frag deine Daten, statt durch Dashboards
zu klicken." Bonus-Argumente: keine Tabs, Custom Events first-class,
GDPR-easy (EU-Hosting auf Hetzner Falkenstein), kein Cookie-Banner nötig
im Strict-Modus.

## TARGET USER

Indie SaaS Founder, Bloggers, Newsletter-Operators, Side-Project-Bauer.
Leute, die Claude oder vergleichbare AI-Tools täglich nutzen und ihre
Analytics nicht in einem separaten Tool haben wollen.

## INFRASTRUKTUR  — `[DONE]`

- 1 Server: Hetzner CX32 (4 vCPU, 8GB RAM, 80GB SSD), Standort Falkenstein,
  IP `49.13.165.191`
- ClickHouse direkt auf der Server-SSD unter /var/lib/clickhouse
- Tägliche automatische Backups via `ops/backup.sh`
- Domains: `mcp-analytics.com` (web) + `t.mcp-analytics.com` (ingest)
- Deployment: Kamal 2, alles als Docker-Container, zsh-wrapper-Trick
  beim Deploy notwendig (siehe CLAUDE.md)
- Reverse Proxy / TLS: kamal-proxy + Let's Encrypt automatisch

## STACK  — `[DONE]`

- Rails 8 App (Container 1)
  - SQLite für Account/Site/Token-Daten
  - Solid Queue für Background-Jobs (Salt-Rotation, Mail-Versand,
    Usage-Counter-Aggregation)
  - Verantwortlich für: Web-UI (nur Verify-Page + Settings + Landing),
    MCP-Server, Auth, Account-Management
- Ingestion-Service (Container 2)
  - Empfehlung: Go-Binary (kleine Footprint, performant, weniger
    Dependencies). Wenn Go zu komplex: in Rails integrieren ist okay
    für MVP-Scale.
  - Endpoints: POST /event, GET /script.js
  - Buffert Events, schreibt mit ClickHouse async_insert
- ClickHouse (Container 3, Accessory in Kamal)
  - Single Node, Persistenz unter /var/lib/clickhouse

> **Status**: Entscheidung für Go-Binary umgesetzt. Rails-App, Go-Service
> und ClickHouse-Accessory sind alle in `config/deploy.yml` definiert.
> Shared Storage-Volume via `mcp_storage:/rails/storage` (SQLite im
> WAL-Mode wird von Rails + Go parallel gelesen).

## OFFENE TECHNISCHE FRAGE (RECHERCHE NÖTIG VOR IMPLEMENTATION)  — `[DONE]`

Welcher Auth-Mechanismus für Remote-MCP-Server ist der korrekte Weg
in 2026? Optionen:
- URL-Query-Param-Token (?token=xxx) – funktioniert, aber unschön
- Bearer-Token im Authorization-Header – sauberer
- OAuth 2.0 Authorization Code Flow – Anthropic-empfohlen, aber komplex
Vor Implementation in der aktuellen Anthropic-Doku zu Remote MCP Servern
nachlesen und passende Variante wählen. Empfehlung als Default:
Bearer-Token im Header, falls OAuth-Setup zu aufwändig für MVP.

> **Entscheidung MVP**: Bearer-Header als primärer Weg, `?token=` als Fallback
> (für Clients, die keinen Custom-Header setzen können). Implementiert in
> `app/controllers/mcp_controller.rb` (`authenticate_from_request`).
>
> **Phase 2 (geplant)**: OAuth 2.1 Authorization Code Flow mit PKCE
> nachrüsten. Siehe Sektion *OAUTH ROADMAP* unten — wird benötigt für
> ChatGPT-Connectors (Pflicht), Anthropic-Directory-Listing (Pflicht) und
> bessere User-Experience (kein Token-Paste mehr).

## DATENMODELL: Rails (SQLite)  — `[DONE]`

users:
  - email (unique)
  - api_token (unique, SecureRandom.urlsafe_base64(32))
  - email_verified_at
  - plan (default 'free' – nur 'free' im MVP relevant)
  - timestamps

sites:
  - user_id
  - domain
  - site_id (8-char base32, public, unique)
  - privacy_mode ('strict' | 'default' | 'all', einmalig bei add_site
    festgelegt, später nicht änderbar)
  - site_salt (random bei Erstellung, für Session-ID-Hashing)
  - salt_rotated_at
  - created_at, updated_at, deleted_at (soft-delete)

email_verifications:
  - email
  - verify_token (SecureRandom.urlsafe_base64(32))
  - pending_user_id (öffentliche ID, z.B. "pu_" + 8 base32 chars)
  - expires_at (24h nach Erstellung)
  - used_at
  - created_at

magic_links (für Settings-Login):
  - user_id
  - token (long random)
  - expires_at (15 min)
  - used_at
  - created_at

usage_counters:
  - site_id
  - month (Date, 1. des Monats)
  - hit_count
  - unique index on [site_id, month]
  - hit_count wird async vom Ingestion-Service hochgezählt
    (gepuffert, nicht pro Event)

unknown_site_hits (Anti-Abuse):
  - site_id_attempted (string)
  - hit_count
  - hour (DateTime, gerundet auf Stundenanfang)
  - unique index on [site_id_attempted, hour]
  - wenn pro IP/Stunde >X Garbage-Site-IDs auftauchen: Alert an Operator

> **Status**: Alle 6 Migrations unter `db/migrate/` + Models in
> `app/models/`. Schreiben der `usage_counters`/`unknown_site_hits` aus
> Go via buffered UPSERT (`ingestion/internal/usage/buffer.go`).
>
> **Offen**: Die Garbage-Site-ID → IP-Block-Logik (siehe ANTI-ABUSE).

## DATENMODELL: ClickHouse  — `[DONE]`

CREATE TABLE events (
    site_id        UInt32,
    timestamp      DateTime64(3, 'UTC'),
    event_name     LowCardinality(String),
    session_id     UInt64,
    visitor_id     UInt64,           -- 0 in strict-mode
    url_path       String,
    url_host       LowCardinality(String),
    referrer_host  LowCardinality(String),
    referrer_path  String,           -- nur in default/all
    utm_source     LowCardinality(String),
    utm_medium     LowCardinality(String),
    utm_campaign   LowCardinality(String),
    browser        LowCardinality(String),
    browser_version LowCardinality(String),
    os             LowCardinality(String),
    device_type    LowCardinality(String),
    country        LowCardinality(String),  -- leer im MVP
    region         LowCardinality(String),  -- leer im MVP
    city           LowCardinality(String),  -- leer im MVP
    prop_keys      Array(String),
    prop_values    Array(String),
    ingested_at    DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(timestamp)
ORDER BY (site_id, timestamp, event_name)
TTL timestamp + INTERVAL 2 YEAR
SETTINGS index_granularity = 8192;

Plus zwei Materialized Views für häufige Aggregationen:

CREATE MATERIALIZED VIEW events_hourly
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (site_id, hour, event_name, url_path)
AS SELECT
    site_id,
    toStartOfHour(timestamp) as hour,
    event_name,
    url_path,
    count() as events,
    uniqState(session_id) as sessions_state,
    uniqState(visitor_id) as visitors_state
FROM events
GROUP BY site_id, hour, event_name, url_path;

CREATE MATERIALIZED VIEW referrers_daily
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (site_id, day, referrer_host)
AS SELECT
    site_id,
    toDate(timestamp) as day,
    referrer_host,
    count() as visits,
    uniqState(session_id) as sessions_state
FROM events
WHERE event_name = 'pageview' AND referrer_host != ''
GROUP BY site_id, day, referrer_host;

Geo-Spalten bleiben im MVP leer. MaxMind-Lookup kommt in einer späteren
Iteration ohne Schema-Migration. Später hinzukommende Spalten (Web Vitals,
Conversion-Tracking, A/B-Test-IDs) können per ALTER TABLE ADD COLUMN
problemlos angefügt werden.

> **Status**: Alle drei DDLs liegen in `clickhouse/init/` und werden beim
> ClickHouse-Container-Start eingespielt. HTTP-Client für Rails:
> `lib/click_house.rb`. Go-seitig: `ingestion/internal/ch/client.go`
> (async_insert Batcher, Flush alle 5s oder 1000 Events).

## PRIVACY MODES (per Site bei add_site() gewählt, NICHT änderbar)  — `[DONE]`

strict (Default-Empfehlung für EU-Sites):
  - Daily Salt rotiert um Mitternacht UTC
  - session_id = sha256(daily_salt + site_salt + ip + user_agent + site_id)
                   gekürzt auf 8 bytes als UInt64
  - visitor_id = 0 (nicht trackbar über 24h)
  - Geo: nur Country (im MVP komplett leer da kein MaxMind)
  - Referrer: nur Host, kein Path
  - Kein Cookie, kein localStorage
  - Kein Cookie-Banner nötig
  - Respektiert Do-Not-Track als hartes Opt-Out

default:
  - site_salt rotiert alle 365 Tage
  - session_id wie oben aber mit langlebigem Salt
  - visitor_id = sha256(site_salt + ip + ua + site_id) gekürzt auf UInt64
    (ohne daily-Komponente, persistent über Salt-Lebensdauer = 365 Tage)
  - Geo: Country, Region, City (im MVP leer)
  - Referrer mit Path
  - Volle Browser-Detection
  - Kein Cookie technisch nötig, aber Site-Owner sollte
    Cookie-Banner-Pflicht eigenständig prüfen (EU)

all:
  - Persistent Cookie _mcpa_id (2 Jahre) plus localStorage Backup
  - visitor_id aus Cookie
  - Cross-Subdomain möglich
  - Maximale Daten-Retention
  - Site-Owner verantwortlich für GDPR/CCPA-Compliance
  - DNT wird respektiert wenn vom Site-Owner aktiviert (Setting)

In allen Modi: NIEMALS PII speichern (Email, Namen, IDs aus
Site-eigenen User-Systemen). Custom Events können das versehentlich
mitschicken – Backend filtert/warnt nicht, ist Verantwortung des
Site-Owners.

> **Status**: Salt-Logik in `ingestion/internal/session/id.go`. Daily-Salt-
> Rotation via `RotateDefaultSaltsJob` (läuft 03:17 UTC, siehe
> `config/recurring.yml`). Cookie-basierter `all`-Mode im Tracking-Script
> implementiert.

## TRACKING-SCRIPT (~50-80 Zeilen Vanilla JS)  — `[DONE]`

Ausgeliefert unter https://mcp-analytics.com/script.js (extern,
gecached). Self-hosted-Variante kommt in späterer Phase.

Funktionalität:
- Auto-Pageview beim Load
- SPA-Support: Hooks in history.pushState / popstate
- Manuelles Event API: window.mcpa('track', 'event_name', {prop: value})
- Headless-Detection (filtert offensichtliche Bots client-side ohne
  Request zu senden)
- Sendet via navigator.sendBeacon() an /event
- Respektiert Do-Not-Track (im strict-Mode hartes Opt-Out)
- Property-Limits: max 20 keys, max 10kb total per Event,
  Werte nur primitive Types (string, number, bool)

Snippet zum Einbauen:
<script defer data-site="abc12345" 
        src="https://mcp-analytics.com/script.js"></script>

Während der "Pre-Verify"-Phase nutzt Claude den Platzhalter
DUMMY_SITE_ID_REPLACE_AFTER_VERIFY als data-site Wert. Der User
ersetzt diesen später per Suchen+Ersetzen mit der echten Site-ID.

> **Status**: `ingestion/static/script.js` — 131 Zeilen, wird vom Go-
> Service unter `https://t.mcp-analytics.com/script.js` ausgeliefert
> (nicht unter `mcp-analytics.com/script.js` wie ursprünglich im Briefing).
>
> **Hinweis**: Im README wird konsequent `t.mcp-analytics.com` dokumentiert.
> Vor Launch prüfen, ob das Public-Snippet in Marketing/Landing die
> richtige URL zeigt.

## INGESTION-FLOW  — `[DONE]`

POST /event Body:
{
  "site": "abc12345",
  "name": "pageview" | "<custom>",
  "url": "https://example.com/path?utm_source=...",
  "referrer": "https://google.com/search?q=...",
  "props": { "plan": "pro" }     // optional, max 20 keys
}

Server-Verarbeitung:
1. Validierung: site_id existiert? Wenn nicht: 204 zurück, in
   unknown_site_hits zählen (Anti-Abuse-Telemetrie). KEIN Error,
   damit "Pre-Verify"-Tracking sauber failed-silent ist.
2. Rate-Limit check pro site_id (siehe ANTI-ABUSE)
3. Bot-Filter: UA-Liste (isbot-äquivalent), drop wenn Match
4. Salt-basierte Session/Visitor-ID berechnen je nach privacy_mode
5. UA parsen (browser, browser_version, os, device_type)
6. Referrer parsen (host, path)
7. UTM aus URL-Query extrahieren, dann Query-String aus url_path strippen
8. Event in In-Memory-Buffer (oder direkt mit ClickHouse async_insert)
9. Batch-Flush alle 5s oder bei 1000 Events
10. Async: usage_counters in SQLite hochzählen (gepuffert, alle 30s)
11. Response: 204 No Content (so schnell wie möglich, keine JSON-Response)

Bot-Filter-Strategie:
- 8-Klassen-Klassifikation beim Ingest (`internal/classify`):
  UA-Pattern + IP-CIDR-Trie (refresh alle 6h) + Reverse-DNS für
  Anthropic + Generic-Browser-from-Cloud-Heuristik
- Headless-Browser-Marker im Tracking-Script vorab filtern
  (navigator.webdriver, etc.)

> **Status**: Alle Schritte 1–11 umgesetzt in
> `ingestion/internal/server/server.go` + Packages `classify`, `ratelimit`,
> `session`, `ua`, `ch`, `usage`, `sites`. Phase-1 binary `bot/`-Package
> ist seit Phase-2-Deploy nicht mehr im Hot-Path.
>
> Die im Original-Briefing skizzierte MV-Bot-Heuristik (Sessions mit
> >5 Events/Sek aus den Materialized Views ausklammern) wird nicht
> implementiert — Phase 2 fängt die meisten Spoofer schon vor der
> Aggregation, der zusätzliche MV-Filter wäre redundant.

## MCP-SERVER  — `[DONE]`

EINE MCP-URL für alles, mit Conditional Tools je nach Auth-Status:

URL: https://mcp-analytics.com/mcp
- Ohne Auth-Token: zeigt nur Signup-Tools
- Mit Auth-Token (über Bearer-Header oder Query-Param, je nach
  Recherche-Ergebnis): zeigt Analytics-Tools

Das hat den Vorteil, dass der User nur EINE Connector-URL hinzufügen
muss und sie später nur um den Token-Param erweitert.

### UNAUTHENTICATED TOOLS (Signup-Phase)

register_account(email: string)
  → backend: erstellt email_verification record mit verify_token + 
    pending_user_id, schickt Mail mit Link 
    https://mcp-analytics.com/verify/<verify_token>
  → response: {
      pending_user_id: "pu_abc12345",
      placeholder_site_id: "DUMMY_SITE_ID_REPLACE_AFTER_VERIFY",
      message: "Bestätigungsmail an X gesendet. Du kannst jetzt
                schon den Tracking-Code mit dem Platzhalter einbauen.
                Nach Verifizierung tauschst du den Platzhalter gegen
                die echte Site-ID aus."
    }
  → Rate-Limits: 3 pro IP/Stunde, 10 pro IP/Tag, 5 pro Email-Domain/Tag
  → Email-Provider-Blacklist für Wegwerfmail-Domains (10minutemail etc.)

get_started_guide()
  → Markdown mit Erklärung des kompletten Flows
  → erklärt Claude wie Pre-Verify-Tracking funktioniert (Platzhalter)
  → erklärt User-Steps (Mail klicken, Token kopieren, Connector
    aktualisieren)

### AUTHENTICATED TOOLS (mit Token)

list_sites()
add_site(domain, privacy_mode = 'strict')
get_tracking_snippet(site_id)
remove_site(site_id)
get_overview(site_id, period = 'last_7_days')
get_timeseries(site_id, metric, period, granularity = 'day')
top_pages(site_id, period, limit = 10)
top_referrers(site_id, period, limit = 10)
top_sources(site_id, period, limit = 10)
breakdown(site_id, dimension, period, limit = 10)
list_events(site_id, period)
event_details(site_id, event_name, period, group_by_property?)
compare_periods(site_id, metric, period_a, period_b)
get_account()
regenerate_api_token()

Auth-Layer: Token aus Header oder Query-Param lesen, User finden, alle
Queries automatisch nach user.sites scopen. Kein Cross-Tenant-Zugriff
möglich.

Rate-Limit MCP-Auth-Tools: 60 requests/min pro User.

EXPLIZIT NICHT ENTHALTEN: query_sql oder andere Power-User-Tools.
Diese sind als Enterprise-Offramp reserviert (siehe ENTERPRISE).

> **Status**: Alle 18 Tools implementiert in `app/services/mcp/tools.rb`,
> JSON-RPC Dispatch in `app/services/mcp/server.rb`, Auth + Rate-Limit
> in `app/controllers/mcp_controller.rb` (60 req/min per Token,
> `McpRateBucket`). Tool-Schemas in `app/services/mcp/tool_schemas.rb`.
> Started-Guide als Markdown in `app/services/mcp/started_guide.md`.
>
> **Offen bestätigen**: Rate-Limits für `register_account`
> (3/IP/h, 10/IP/d, 5/Domain/d) — Implementation prüfen, ist im
> Briefing unter ANTI-ABUSE genauer spezifiziert.

## REGISTRIERUNGS-FLOW (END-TO-END)  — `[DONE]`

1. User: "Bau mir eine Tierbilder-Seite und nutze mcp-analytics"
2. Claude: "Connector hinzufügen: https://mcp-analytics.com/mcp"
3. User aktiviert Connector.
4. Claude: `register_account(email)` → pending_user_id + Platzhalter-ID
5. Claude baut Seite mit Platzhalter `DUMMY_SITE_ID_REPLACE_AFTER_VERIFY`
6. Claude: "Mail bestätigen, Token holen, Connector aktualisieren."
7. User: Mail-Link → `/verify/<token>` → Verify-Page mit Token + MCP-URL
8. User aktualisiert Connector-URL.
9. Claude: `list_sites()` + `add_site(...)` → echte site_id
10. Claude: "Suchen+Ersetzen Platzhalter → echte ID."
11. Done.

> **Status**: Alle Bausteine vorhanden (Tools, Verify-Controller,
> VerificationMailer). End-to-End-Test steht aus (siehe
> Dogfooding/Tests).

## WEB-UI (MINIMAL)  — `[DONE]`

GET /                 Landing (statisch)
GET /verify/:token    Email-Verify + Token-Anzeige
GET /settings         Magic-Link-auth, Token regenerieren, Sites, Löschen
POST /magic-link      Login-Link senden

KEINE Analytics-UI. Datenansicht ausschließlich über MCP.

> **Status**: Controller unter `pages`, `verifications`, `sessions`,
> `settings`. Views komplett. Routes in `config/routes.rb`.

## ANTI-ABUSE  — `[DONE]`

Rate-Limits:
- register_account: 3 pro IP/Stunde, 10 pro IP/Tag, 
                    5 pro Email-Domain/Tag
- magic_link: 5 pro Email/Stunde
- add_site (auth): 10 pro User/Tag
- /event Endpoint: 100 Events/Sekunde pro site_id als Soft-Limit,
                   darüber wird verworfen ohne Error
- MCP-Queries: 60/Minute pro User

Email-Provider-Blacklist für Trash-Mail-Domains (öffentliche Listen
von GitHub als Startpunkt, manuell pflegbar).

Free-Tier-Limit-Verhalten:
- 100k Hits/Monat pro User-Account (Summe über alle Sites, NICHT pro Site)
- Bei Überschreitung: Events werden weiterhin angenommen (nicht
  verworfen), aber MCP-Queries returnen Warning "Limit überschritten,
  Daten ab Datum X unvollständig" + Hinweis auf Enterprise
- Operator (Alex) bekommt Mail wenn ein User >150% Limit erreicht
  (potentieller Enterprise-Lead)

Garbage-Site-ID-Detection:
- unknown_site_hits Tracking pro site_id_attempted
- Wenn pro IP/Stunde >100 Garbage-Site-IDs auftauchen: IP-Block 1h
- Operator-Mail bei wiederholtem Pattern

> **Status**: alles `[DONE]` außer Email-Blacklist-Refresh.
> - 60/min MCP-Queries (`McpRateBucket`)
> - 100 Events/s per site_id (`ingestion/internal/ratelimit`)
> - Free-Tier-Alert via `UsageLimitAlertJob`
> - `unknown_site_hits` werden geschrieben + IP-Block bei >100/h via Go `ipblock`
> - Operator-Digest via `AbuseAlertJob` (5-Min-Bündelung)
> - Rate-Limits `register_account` (3/IP/h, 10/IP/d, 5/Dom/d), `magic_link`,
>   `add_site` alle live in Controllern
> - `[PARTIAL]` Email-Blacklist: `disposable_email_domain?` prüft, Liste
>   sollte regelmäßig gegen aktuelle GitHub-Liste abgeglichen werden

## ENTERPRISE-OFFRAMP  — `[SKIP im MVP]`

Wenn User mehr will (höhere Limits, query_sql, dedicated Server, SLA,
Geo-Daten, Custom Domain für Tracking):
Verweis auf Kontaktformular / Email an enterprise@mcp-analytics.com.
Manueller Sales-Prozess, nicht im MVP automatisiert.

## EXPLIZIT NICHT IM MVP  — `[SKIP]`

- Stripe / Bezahlfunktion
- query_sql Power-Tool
- Web-Signup-Formular (Signup ausschließlich via MCP)
- Dashboard / UI für Analytics
- Goal/Funnel-Builder
- Realtime-View
- A/B-Testing-Integration
- Datenexport
- MaxMind Geo-Lookup (Schema vorbereitet, leer)
- Mehrere Server / Cluster
- Team-Accounts (jeder User ist single-tenant)
- HTTP-API neben MCP
- Webhooks
- Custom Domains für Tracking-Endpoint
- Self-hosted Tracking-Script Variante
- npm-Paket für Tracker
- Anthropic Connector-Directory-Eintrag
- Performance-Metriken / Web Vitals
- Conversion-/Revenue-Tracking
- Ad-blocker-Workaround via Subdomain-Proxy

## ROADMAP NACH MVP (aktualisiert 2026-05-07)

Original-Briefing hatte hier 4 grobe Phasen. Aktueller Stand nach
Pricing-Strategie (siehe `PRICING.md`):

- **Pro-Tier-Features** (€19/Mo): Bot-Phase 2 Taxonomie + Phase 4
  Server-Side-Ingestion (Ruby/Node/Pixel/Edge) + Deploy-Regression
  GH-Action + `record_event`. Diese existieren noch nicht im Code,
  stehen aber auf der Pricing-Page als "very soon"/"soon"/"soon-ish".
- **Enterprise-Tier-Features** (ab €299/Mo): dedicated Host, `query_sql`
  Power-Tool, MaxMind Geo-Lookup, custom Tracking-Domain, white-label
  Skript, Web Bot Auth Signature Verification (Bot-Phase 3), DPA/SAML/
  Audit-Log. Existing `enterprise@`-Funnel ist Lead-Source.
- **2. Säule (post 50 zahlende Kunden)**: MCP-Server-Analytics
  (`Plausible für MCP-Server`). Eigene Produktlinie, nicht in Pillar 1
  Tiers gemixt. Design-Doc weiter unten.

## ERFOLGSKRITERIEN MVP

Funktional (alle Code-verifiziert + in Production):
- [x] Tracking-Snippet einbinden → Events landen in ClickHouse
- [x] Über MCP in Claude → Daten kommen zurück
- [x] Signup-Flow E2E inkl. OAuth-Consent-Flow
- [x] Mehrere Sites parallel ohne Daten-Leak
- [x] 3 Privacy-Modi sauber implementiert
- [x] Garbage-Events gegen unbekannte Site-IDs failed silent + IP-Block

Performance (noch nicht final unter Last gemessen):
- [ ] Ingestion <50ms p99
- [ ] MCP-Query <500ms p95 für Standard-Tools
- [ ] 100 aktive Sites parallel auf einem CX32 ohne Probleme

Operational:
- [x] Kamal-Deploy funktioniert (zsh-wrapper-Trick siehe CLAUDE.md)
- [x] Backup automatisiert (`ops/backup.sh` täglich)
- [x] Monitoring: Garbage-Site-Hit-Alert + Free-Tier-Alert via Mail done
- [ ] Monitoring: Uptime + Disk-Alert (UptimeRobot + `df`-Warning) noch offen

## ZEITLICHE EINORDNUNG

Original-Briefing schätzte 4-6 Wochen für MVP. Tatsächlich:

| Phase                                                           | Status       | Datum            |
|-----------------------------------------------------------------|--------------|------------------|
| Wochen 1-4: Infra + Datenmodell + MCP + UI                      | `[DONE]`     | bis 2026-04-23   |
| Bot-Klassifikation Phase 1                                      | `[DONE]`     | 2026-04-27       |
| Landing-Page brutalist                                          | `[DONE]`     | 2026-04-24       |
| OAuth Phase 2 (Authorization Code + PKCE + DCR + RFC 8707)      | `[DONE]`     | 2026-05-02       |
| OAuth Hardening (Revocation, Audit-Log, Rate-Limits, Settings)  | `[DONE]`     | 2026-05-05       |
| Production-Deploy auf Hetzner                                   | `[DONE]`     | Mai 2026         |
| Pricing-Strategie + Landing-Section                             | `[DONE]`     | 2026-05-07       |
| **Pricing-Implementation (Stripe + Tier-Enforcement)**          | `[TODO]`     | nächste Phase    |
| Bot-Phase 2 (Cloudflare-Taxonomie, 8 Klassen)                   | `[DONE]`     | 2026-05-07       |
| **Bot-Phase 4 (Server-Side-SDK) als Pro-Tier-Feature**          | `[TODO]`     | parallel         |
| **Dogfooding + Directory-Submissions**                          | `[TODO]`     | nach Pro-Launch  |

---

## OPEN ACTIONS (Stand 2026-05-07)

P0/P1-Launch-Block ist durch (Hetzner-Deploy + DNS + Backup + Smoke-Test
alles done; OAuth Phase 2 + Hardening live; Tests grün; Bot-Phase 1+2
shipped). Was jetzt noch offen ist:

### A — Pricing-Implementation (vor Pro-Launch nötig)

Volle Liste mit Aufwand und Begründung in `PRICING.md` §9. Zusammenfassung:

1. **`subscriptions`-Modell + `tier`-Enum** auf User (`hobby`/`pro`/`enterprise`). ~4h.
2. **Tier-Enforcement im `Mcp::AuthContext`** — Bot-/SDK-/Deploy-Tools nach Tier schalten. ~4h.
3. **Hits-Cap Hard-Enforcement** für Free — heute Soft-Warning, muss 429 für Free über Cap werden. ~2h.
4. **Stripe-Checkout + Webhook** (oder Lemon-Squeezy als EU-VAT-Merchant-of-Record). ~1-2 Tage.
5. **Overage-Cron** — Solid-Queue Monats-Ultimo, summiert Hits über Cap, `Stripe::InvoiceItem`. ~2h.
6. **Settings-UI für Auto-Overage opt-in** — Toggle + Stripe-Card-Setup. ~3h.

### B — Pro-Tier-Features die noch nicht im Code sind

Diese stehen auf der Pricing-Page als "very soon"/"soon"/"soon-ish":

7. ~~**Bot-Phase 2** Cloudflare-kompatible Taxonomie~~ ✅ done 2026-05-07 (`internal/classify`).
8. **Bot-Phase 4B** Ruby-Gem `mcp-analytics-rack`. "Biggest Unlock". ~3h.
9. **Bot-Phase 4A/C/D** Pixel-Endpoint + Node/Next-Middleware + CF-Worker. ~4h zusammen.
10. **`record_deploy` + `regression_check` MCP-Tools** + GitHub-Action `mcp-analytics/record-deploy@v1`. ~3-4h.

### C — Restliche Hygiene

11. **CI-Workflow re-enablen** — `.github/workflows/` hat nur dependabot.yml; 129 grüne Tests warten.
12. **Email-Domain-Blacklist refresh** gegen aktuelle GitHub-Liste.
13. **Uptime/Disk-Monitoring** — UptimeRobot + `df`-Warning bei >80%. (Usage-Alert + Garbage-Pattern sind durch.)

### D — Distribution / Marketing

15. **Dogfooding** retreaturlaub.de + triageflow.com.
16. **Cursor-Directory-Submission** (niedrige Hürde, Indie-Dev-Reichweite).
17. **Anthropic Connector-Directory-Submission** (OAuth ist live → eligible).
18. **ChatGPT Connectors-Submission** (OAuth + DCR sind live → eligible).
19. **Landing Copy + Demo-Video** wenn Pro-Tier-Features sichtbar sind.

Siehe auch `## DIRECTORY-SUBMISSIONS — Status-Tracking` unten für laufende Submissions.

### E — Strategische 2. Säule (geparkt)

20. **MCP-Server-Analytics** als zweite Produktsäule (`Plausible für MCP-Server`).
    Im PRICING.md bewusst aus Y1-Pricing rausgelassen — startet erst nach
    50 zahlenden Web-Analytics-Kunden. Design-Doc in dieser BRIEFING.md
    weiter unten.

### Offene Detail-Frage (im Code geklärt, nur Doku-Aufgabe)

- ✅ Tracking-Script-URL ist im Code konsistent `t.mcp-analytics.com/script.js`
  (siehe `config/deploy.yml`, `tools.rb`, `home.html.erb`). Briefing-Text
  weiter unten erwähnt teilweise noch `mcp-analytics.com/script.js` — kann
  bei Gelegenheit angepasst werden, aber Code ist die Source-of-Truth.

---

## DIRECTORY-SUBMISSIONS — Status-Tracking

Submissions an externe MCP-Direktories werden manuell reviewed. Listings
können 1-21 Tage dauern oder ganz versanden. Hier die Liste aller
eingereichten — **regelmäßig prüfen ob veröffentlicht wurde**.

Empfohlener Rhythmus: **alle 7 Tage** durchgehen, bei länger als 21 Tagen
ohne Reaktion freundlich nachfassen oder erneut einreichen.

| Datum eingereicht | Direktory | URL | Status | Letzter Check |
|---|---|---|---|---|
| 2026-04-27 | mcpservers.org | https://mcpservers.org | ⏳ pending review | — |
| 2026-04-27 | mcp.so | https://mcp.so | ⏳ pending review | — |
| 2026-04-27 | sylviangth/awesome-remote-mcp-servers | GitHub PR | ⏳ pending merge | — |

**Status-Codes:**
- ⏳ pending — eingereicht, wartet auf Review
- ✅ live — listed + verlinkt
- ❌ rejected — abgelehnt (Grund eintragen, ggf. anpassen + neu einreichen)
- 🚫 ghosted — > 21 Tage keine Reaktion, Folgemaßnahme prüfen

**Wenn etwas LIVE geht:**
- Listing-URL eintragen
- Backlink von dort prüfen (DoFollow vs NoFollow — beeinflusst SEO-Wert)
- Falls möglich, Click-Through-Tracking einrichten (eigene Site-IDs in URL-Params, e.g. `?utm_source=mcp.so`)

**Noch nicht eingereicht** (Pipeline für nächste Sessions):

| Direktory | URL | Hürde |
|---|---|---|
| modelcontextprotocol.io/registry | offizielle Anthropic Registry | mittel — Format-strikt |
| Smithery | smithery.ai | mittel — eigene Install-Pipeline |
| Glama | glama.ai/mcp | niedrig — Form |
| PulseMCP | pulsemcp.com | niedrig — Form |
| wong2/awesome-mcp-servers | GitHub | niedrig — PR |
| punkpeye/awesome-mcp-servers | GitHub | niedrig — PR |
| appcypher/awesome-mcp-servers | GitHub | niedrig — PR |
| Cursor Directory | cursor.directory/plugins | niedrig — Form |
| Anthropic Connector Directory | claude.com/docs/connectors/building/submission | hoch — verlangt OAuth + Privacy Policy + Public Docs (Phase 2) |
| ChatGPT Connectors | OpenAI partner program | hoch — verlangt OAuth + DCR (Phase 2 + 4) |

---

## OAUTH ROADMAP — `[DONE 2026-05-02 + Hardening 2026-05-05]`

**Live in Production.** Authorization-Code-Flow mit PKCE, Dynamic Client
Registration, RFC 8707 Resource Indicators, Two-Scope-Modell
(`analytics:read` + `analytics:manage`), Revocation-Endpoint (RFC 7009),
Audit-Log, Settings-UI für Connector-Management. Code in
`app/controllers/oauth/` + `app/services/oauth/` + `app/views/oauth/`.

Kritische Compat-Quirks die wir gefunden haben (claude.ai-Frontend ist
strict): siehe **CLAUDE.md** unter "claude.ai's MCP-OAuth integration is
brittle". Architektur-Rationale unten als Reference belassen.

**Warum überhaupt**: ChatGPT-Connectors erzwingen OAuth 2.1, Anthropic-
Directory will es, Cursor empfiehlt es. Außerdem deutlich bessere UX:
kein Token-Paste, kein URL-Editieren, ein Klick-Flow.

### Zielfluss (Variante B — Consent-Screen nach Magic-Link-Click)

Vollständiger End-to-End-Flow für einen **neuen User** (mit Account-Anlage
in einem Rutsch):

```
1. User entdeckt mcp-analytics.com (Landing)
2. User trägt URL "https://mcp-analytics.com/mcp" als Custom Connector
   in Claude/ChatGPT/Cursor ein (kein Token!)
3. Client POSTet auf /mcp ohne Auth
        ↓
4. Server: 401 + Header
   WWW-Authenticate: Bearer
     resource_metadata="https://mcp-analytics.com/.well-known/oauth-protected-resource"
        ↓
5. Client öffnet automatisch Browser-Tab:
   https://mcp-analytics.com/oauth/authorize
     ?client_id=<client>
     &redirect_uri=<client-callback-url>
     &response_type=code
     &state=<csrf-token>
     &code_challenge=<pkce-challenge>
     &code_challenge_method=S256
     &scope=analytics:read%20analytics:manage
     &resource=https%3A%2F%2Fmcp-analytics.com%2Fmcp
        ↓
6. Server prüft Session:
   - eingeloggt? → direkt zu Schritt 9 (Consent-Screen)
   - NICHT eingeloggt? → session[:return_to] = aktuelle URL,
     redirect zu /login
        ↓
7. /login zeigt Email-Feld, User tippt Email,
   Magic-Link wird verschickt
        ↓
8. User klickt Mail-Link → /auth/:token
   - Account wird erstellt, falls neu
   - Session wird gesetzt
   - redirect zu session[:return_to] = /oauth/authorize?... (alle Params
     erhalten weil in der URL kodiert)
        ↓
9. Server rendert Consent-Screen:
   ┌─────────────────────────────────────────────┐
   │ Claude möchte auf dein mcp-analytics-Konto  │
   │ zugreifen:                                   │
   │   • Sites lesen                              │
   │   • Analytics-Daten abfragen                 │
   │   • Neue Sites hinzufügen                    │
   │ Eingeloggt als: alex@example.com             │
   │   [Erlauben]    [Ablehnen]                   │
   └─────────────────────────────────────────────┘
        ↓
10. User klickt [Erlauben]:
    - Server generiert kurzlebigen Authorization-Code (10 min Gültigkeit)
    - speichert (code, user_id, code_challenge, redirect_uri, scope)
    - 302 redirect zu Client:
      <client-callback-url>?code=<code>&state=<state>
        ↓
11. Client tauscht Code gegen Access-Token:
    POST /oauth/token
    Body: grant_type=authorization_code, code=..., redirect_uri=...,
          client_id=..., code_verifier=<pkce-verifier>
    Response: { access_token, token_type: "Bearer", expires_in, ... }
        ↓
12. Client speichert Token intern, sendet ab jetzt jeden /mcp-Request
    mit Authorization: Bearer <token>
        ↓
13. Done. User hat NIE einen Token gesehen oder kopiert.
```

Aus User-Sicht: **Add Connector → eine Mail → ein Klick auf Erlauben →
zurück in Claude/ChatGPT/Cursor, fertig.**

### Implementierung — `[DONE]`

Alles umgesetzt: Discovery-Endpoints, Authorize/Token-Endpoints,
McpController-401-Patch, OAuth-Tabellen (`oauth_clients`,
`oauth_authorization_codes`, `oauth_access_tokens`, `oauth_audit_events`),
Settings-UI mit Revoke pro Connector. Code in
`app/controllers/oauth/`, `app/services/oauth/`, `app/views/oauth/`.
DCR + Refresh-Tokens kamen mit Hardening-Block 1 (2026-05-05) dazu.

### Architektur-Entscheidungen (rückblickend, Code-verifiziert)

- **Two-Scope-Modell live**: `analytics:read` (Queries + list_sites)
  und `analytics:manage` (zusätzlich add_site/remove_site/etc.).
  Tools/list filtert nach gewährten Scopes; tools/call verweigert
  mit klarer Fehlermeldung. `regenerate_api_token` ist für OAuth-
  Sessions komplett unsichtbar (sonst könnte ein OAuth-Client den
  Master-Token extrahieren und den OAuth-Lifecycle umgehen).
- **DCR live** (Phase 2 Foundation 2026-05-02). ChatGPT-Listing wird
  damit eligible.
- **Refresh-Tokens live** (Hardening-Block 1, 2026-05-05).
- **PKCE Pflicht**. Kein Secret-basierter Flow.
- **Audit-Log + Revocation-Endpoint (RFC 7009)** live.

### Variante A vs. B — warum B

Variante A (Implicit Consent): Magic-Link-Klick = Account + Auth in einem,
**ohne** Consent-Screen. Spart einen Klick, aber Permission-Visibility
nur in der Email-Vorschau. Risiko bei Directory-Reviews als „dark pattern"
markiert zu werden.

Variante B (Consent nach Login): Magic-Link → Session → Consent-Screen →
Erlauben. Ein Klick mehr, dafür:
- Gleicher Code-Pfad für Neu-User und Bestand-User (nur ein Wartungs-Pfad)
- Audit-sicher gegenüber Directory-Reviewern
- User sieht klar was er erlaubt

**Entscheidung**: Variante B.

### Geklärte Fragen (rückblickend)

- Scopes: zwei Stück, `read` + `manage` (siehe oben).
- Token-Lebensdauer: Access-Token 1 Jahr, Refresh-Token rotierend.
- Legacy `api_token`s: weiterhin akzeptiert (`mcpa_…`-Prefix), Settings
  warnt aber auf OAuth-Variante hin. Query-Param-Form (`?token=`) trägt
  Deprecation-Header — Plan ist Sunset wenn Audit-Log 30 Tage zero use
  zeigt (siehe CLAUDE.md "Followups").

---

## BOT- & AI-AGENT-KLASSIFIKATION (Phase-Plan, post-MVP) — `[PHASE 1 DONE]`

**Warum**: aktuell droppt der Go-Ingest jeden Request mit Bot-UA. Damit
verlieren wir das vielleicht interessanteste Signal eines AI-nativen
Analytics-Tools — Sichtbarkeit darüber, welche AI-Agenten (ChatGPT-User,
Claude-User, Perplexity, GPTBot, …) eine Seite lesen, und welche
Search-Indexer / Social-Unfurler / Scanner sie crawlen. Gleichzeitig
müssen die Default-Customer-Numbers sauber bleiben — Bot-Noise darf nicht
„Pageviews" inflieren.

### State of the Art (Recherche April 2026)

- **Cloudflare AI Crawl Control** (GA Aug 2025) — Klassifikation nach
  Crawl-Purpose: `Training / Search / User-action / Undeclared`. Wird
  de-facto-Schema. Aber Edge-Layer, nur für CF-Kunden.
- **DataDome / TollBit** — Edge-installiert, AI-Bot-Tracking + Monetisierung.
  Enterprise-Pricing.
- **Plausible / Fathom / Umami / Vercel Analytics** — droppen Bots
  pauschal, kein first-class AI-Bot-View. Marktlücke.
- **Web Bot Auth** (IETF Draft, 2025): Ed25519-signierte Agenten,
  Cloudflare + AWS + Visa shippen das schon. OpenAI/Anthropic-Agenten
  signieren teilweise. In 12-18 Monaten DER Verifizierungs-Standard.

### Bekannte AI-Agent UAs (April 2026)

- **OpenAI**: `GPTBot` (Training), `OAI-SearchBot` (Search-Index),
  `ChatGPT-User` (Live-User-Fetch). 3 separate IP-Files publiziert.
- **Anthropic**: `ClaudeBot` (Training), `Claude-User` (User-Fetch),
  `Claude-SearchBot`. **Keine** öffentlichen IP-Ranges → Verifikation
  nur via robots.txt + reverse DNS.
- **Google**: `Googlebot` (Search), `Google-Extended` (Gemini-Training-
  Opt-Out), `Gemini-Deep-Research` (agentic).
- **Perplexity**: `PerplexityBot` (Index), `Perplexity-User` (Live).
- **Apple**: `Applebot` + `Applebot-Extended`.
- **Meta**: `Meta-ExternalAgent`, `meta-externalfetcher`.
- **Andere**: `Bytespider` (ByteDance), `cohere-ai`, `Mistral-User`,
  `CCBot` (Common Crawl, surrogate trainer).
- **Spoofing-Rate**: HUMAN-Report 2025 sagt ~5.7% der „AI-Bot-UAs" sind
  Fakes. UA allein nicht trustworthy → IP-Range + zukünftig Signature
  als zweite Bestätigung.

### Phase 1 — Binary Classification + Raw UA  — `[DONE 2026-04-27]`

Stop dropping bots. Add `traffic_class` (LowCardinality, default 'user')
und `user_agent` (raw String) Spalten zu `events`. Default-MCP-Queries
filtern `WHERE traffic_class = 'user'` automatisch. Zwei neue MCP-Tools
exposen die Bot-Sicht: `top_user_agents` (mit optionalem
`traffic_class`-Filter) und `traffic_class_breakdown`.

**Limit der Phase 1**: nur Bots die JS ausführen (modernes Googlebot,
Headless-Chrome) tauchen auf, weil unser Tracker JS-basiert ist. Der
Großteil der Crawler (GPTBot-Training, ClaudeBot, CCBot, Slackbot,
Censys) ignoriert JS und ist damit unsichtbar in unseren Analytics.
Diese Lücke schließt erst Phase 4 (Server-Side Ingestion).

### Phase 2 — Refined Crawl-Purpose Klassifikation — `[DONE 2026-05-07]`

Implementiert in `ingestion/internal/classify`. `traffic_class` ist
jetzt einer von 8 Werten: `user / ai_user_action / ai_search /
ai_training / search_index / social_unfurl / scanner / bot_other`.

Architektur (siehe `internal/classify/classify.go` für die Decision-Tree-
Doku):

1. **UA-Pattern-Matching** — kuratierte Liste in `ua_patterns.go`
   (~70 Einträge mit Purpose-Mapping). Hauptquelle:
   ai-robots-txt/ai.robots.txt + Anthropic/OpenAI/CF-Radar-Listen.
2. **IP-CIDR-Trie** (`trie.go`) — refreshed alle 6h via
   Background-Goroutine (`refresh.go`) gegen die JSONs von
   OpenAI (3 Endpoints), Google (3), Bing, AWS, GCP, Cloudflare.
   Atomic-Pointer-Swap, Sanity-Check (`MinShrinkRatio` lehnt
   wildlich-geschrumpfte Refreshes ab — fängt z.B. das "OpenAI
   returnt leeres Array"-Failure-Mode), Embedded-Fallback-CIDRs in
   `fallback_ranges.go` für Cold-Start ohne Netzwerk.
3. **FCrDNS für Anthropic** (`dns.go`) — Anthropic publiziert keine
   IP-JSONs; wir verifizieren via Reverse-DNS (`*.anthropic.com`)
   plus Forward-Confirm gegen Spoofing. Cache 24h success / 1h
   failure.
4. **Heuristik** (`classify.go` Step 4) — Generic-Browser-UA + IP
   in Cloud-Infra-Range → `scanner`. Spoof-Detection: Specific-UA
   (z.B. "GPTBot") + IP in fremder Vendor-Range → demote zu
   `bot_other`.

Daily live-source schema-check via
`.github/workflows/ai-crawler-schema-check.yml` — Out-of-Band-Detector
für Endpoint-Moves wie das Google-March-2026-Drift-Event.

Retroactive UA-Reklassifikation für historische Rows:
`go run ./cmd/reclassify --apply` (default dry-run).

Ops-Burden: Ranges automatisch refreshed; UA-Liste alle 1-2 Monate
gegen ai.robots.txt diffen.

### Phase 3 — Web Bot Auth Signature Verification — `[FUTURE]`

Aufwand: ~1 Tag. Trigger: wenn signierte Agenten Mainstream werden
(Schätzung: 2026 H2 / 2027 H1).

Implementation des Web-Bot-Auth-Standards (RFC 9421 HTTP Message
Signatures + Ed25519). Server verifiziert die Signature aus den
`Signature` / `Signature-Input` / `Signature-Agent` Headers. Public-Keys
des Agenten kommen aus `/.well-known/http-message-signatures-directory`
des Agenten-Domains. Erlaubt Marketing-Claim *„this many VERIFIED Claude
agents read your site this week"* — belastbar, nicht UA-Roulette.

### Phase 4 — Server-Side Ingestion (Hybrid Tracking) — `[TODO, BIGGEST UNLOCK]`

Aufwand: ~7h für komplette Implementierung. Trigger: nach Phase 1
Validation, vor breitem Marketing-Push.

**Das Problem**: JS-Tracker sieht keine Bots die JS ignorieren — das
sind ~80% der echten Crawler (GPTBot-Training, Slackbot, Censys, etc.).
Server-side Tracking ist die Lösung — Kunde installiert eine Middleware
die jeden HTTP-Request hinten an unser /event POSTet.

**Datenmodell-Add**: neue Spalte `source` (`tracker` | `server` | `pixel`).
Existing Aggregat-Queries default auf `source IN ('tracker', 'server')`
+ existierender `traffic_class` Filter.

**Drei Implementations-Stufen**:

| 4A | Pixel-Endpoint `/p.gif?site=xxx&path=/` | ~1h |
|---|---|---|
|    | Für static Sites (Astro, Hugo, GitHub-Pages) ohne Server-Runtime. Image-Tag in HTML, jeder Request der Image lädt = 1 Event. Subset-Coverage von Middleware, aber funktioniert auch wo keine Middleware geht. | |
| 4B | Ruby-Middleware-Gem `mcp-analytics-rack` | ~3h |
|    | 50-Zeilen Rack-Middleware. Async Background-POST an /event aus jedem Request. **Fängt ALLE HTTP-Hits inkl. AI-Bots.** Killer-Feature für Indie-Rails-SaaS. | |
| 4C | Node/Next.js/Hono Middleware | ~2h |
|    | Gleicher Spec, TypeScript. NPM publish. | |
| 4D | Cloudflare Worker / Vercel Edge Middleware | ~1h |
|    | Edge-Variante für CF/Vercel-Hostings. Sieht auch CDN-Cache-Hits. | |

**Adoption-Pfad pro Kunde:**

| Stufe | Installation | Was Kunde sieht |
|---|---|---|
| 0 (Default) | Nur JS-Tracker | User-Traffic (heute) |
| + Phase 4B | `gem "mcp-analytics-rack"` + Config | Alles inkl. Bots |
| + Phase 3 | (Server-side, transparent) | Verifizierte Bots |

**Frage „brauche ich Pixel UND Middleware?"**: Nein. Middleware ist eine
Obermenge vom Pixel auf der Origin. Pixel ist nur Fallback für static-only
Sites die keine Server-Runtime haben.

**Marketing-Story nach Phase 4**:
> *„The only privacy-first analytics that shows you which AI agents,
>   search bots, and link unfurlers are reading your content — alongside
>   your real visitors. EU-hosted, MCP-native, no banner needed."*

Plausible/Fathom haben das nicht. Cloudflare hat's nur wenn du CF nutzt.
DataDome ist Enterprise-Pricing. Wir wären in der Privacy-Analytics-Nische
das einzige Tool mit dieser Sichtbarkeit.

---

## SERVER-SIDE MCP-FEATURES (Roadmap, post-MVP) — `[TODO]`

Zwei Features die aus dem MCP-Layer selbst Wertschöpfung ziehen statt nur Daten
ausliefern. Beide kamen aus der Diskussion ums Tracking des Signup-Funnels —
wenn wir clientseitig schon `signup_submitted` tracken, was tracken wir dann
noch serverseitig?

### Feature A — `record_event` MCP-Tool (Server-Side Events) — `~1-2h`

Neues authenticated MCP-Tool: `record_event(site_id, name, properties)`.
Schreibt direkt in ClickHouse `events`, `traffic_class='server'` (oder neue
Klasse `'mcp'`). Use Case: Backend-Conversions ohne extra Library.
Beispiel-Setup für Kunde:
- Stripe-Webhook hookt Claude an → Claude callt `record_event` mit `purchase`
- Cronjob pingt Claude → Claude tracked `daily_report_sent`
- Rails-Callback in `User#after_create` → optional via Webhook

Vorteil: erste Stufe von Phase-4 Server-Side ohne dass Kunde Middleware
installiert. Funktioniert für alles das Claude/MCP erreicht.

Schema:
```ruby
{ name: "record_event",
  description: "Server-side event ingestion. Records a custom event without
  needing the JS tracker. Useful for backend conversions (Stripe webhooks,
  cronjobs) that the browser never sees.",
  inputSchema: {
    site_id: String, name: String, properties: { type: "object" } } }
```

### Feature B — MCP Usage Analytics (Selbsttracking) — `~1-2 Tage`

Wir loggen jeden tool-call: welcher User, welches Tool, welche Args (sanitized),
Latency, Error-Rate. Neue ClickHouse-Tabelle `mcp_calls`. Neues Tool
`get_mcp_usage(period)` exposed das dem Kunden.

Use Cases für Kunde:
- "Welche Analytics-Fragen hat mein Team diese Woche gestellt?"
- "Welche Tools werden nie genutzt? Wo verstehen wir die Daten nicht?"
- Audit-Trail wer was wann abgefragt hat (DSGVO-Pflicht für Teams)

Use Cases intern:
- Welche Tools sind redundant? → killen
- Welche Args sind häufig kaputt? → besseres Schema
- Latency-Hotspots in ClickHouse

Schema-Add:
```sql
CREATE TABLE mcp_calls (
  ts DateTime64(3), user_id String, tool_name LowCardinality(String),
  site_id String, args_hash String, latency_ms UInt32, error UInt8,
  error_class LowCardinality(String)
) ENGINE = MergeTree ORDER BY (user_id, ts);
```

Implementation: `Mcp::Server#handle_tool_call` mit before/after wrap der
Latency misst und Insert in ClickHouse async-pusht.

**Priorität**: A vor B. A ist 2h und schließt eine konkrete Lücke
(Backend-Events). B ist Killer-Feature für Teams aber Single-User-Indie
hat erstmal nichts davon.

---

---

## "PLAUSIBLE FÜR MCP-SERVER" (2. Produktsäule) — `[GEPARKT bis 50 Paid-Kunden]`

> **Update 2026-05-07**: Bewusst aus dem Y1-Pricing rausgelassen (siehe
> PRICING.md). Bleibt als eigenständige zweite Produktlinie für später,
> nicht in Web-Analytics-Tiers gemixt. Trigger zum Reaktivieren: 50
> zahlende Web-Analytics-Kunden, dann eigene Pricing-Ladder. Design-Doc
> bleibt unten erhalten.

**Konzept:** Web-Analytics-Style Tracking, aber für MCP-Server selbst. Wer
einen MCP-Server baut und shipped (Anthropic-Directory-Submitter, Cursor-Plugin
Builder, Indie-MCP-Devs), kriegt heute **null** Visibility ob/wer ihn nutzt.
Lücke im Markt, niemand bedient sie. First-Mover-Position möglich.

### Warum strategisch wichtig

- Brand wird breiter: nicht "Web-Analytics über MCP" sondern "die Analytics-Firma
  für alles MCP". 2. Säule für Show HN Reload.
- Differenziert hart von Plausible/Fathom — die können das nie nachbauen.
- Distribution-Channel: jeder Kunde der unser SDK in seinen MCP einbaut → in
  seiner README "powered by mcp-analytics". Kostenloses Marketing.
- Cross-Sell: Web-Analytics-Kunden die selbst MCP-Server bauen kriegen das
  automatisch dazu.

### Technik (Variante A — SDK/Middleware, RICHTIG)

Kunde importiert ein Package in seinen MCP-Server-Code:

```ruby
use McpAnalytics::Middleware, api_key: "mcps_xxx"
```
```typescript
server.use(mcpAnalytics({ apiKey: "mcps_xxx" }))
```

Middleware wrapped Tool-Dispatch, postet async an `/mcp-event`:
```json
{ "tool": "search_files", "client": "claude.ai",
  "session_id": "...", "latency_ms": 124, "error": null, "ts": "..." }
```

Server-Side: gleicher Go-Ingest-Service, anderer Endpoint, neue ClickHouse-
Tabelle `mcp_calls` (Schema-Vorschlag siehe Server-Side-MCP-Features oben),
neue Aggregations-MCP-Tools für den Kunden.

Variante B (Proxy) — **NICHT machen**. Killer-Latency, vendor-lock-in.

### Neue MCP-Tools für den Kunden

- `get_mcp_server_overview(period)` — total calls, top tool, top client, error rate
- `top_mcp_tools(period, limit)` — welche Tools wie oft
- `mcp_clients_breakdown(period)` — Claude vs Cursor vs ChatGPT vs custom
- `mcp_errors(period)` — welche Tools werfen Errors, mit Sample-Args
- `mcp_latency_distribution(tool, period)` — p50/p95/p99 pro Tool

### Aufwand

~1 Woche MVP: Ruby Gem + Node SDK + Ingestion + ClickHouse-Schema +
4-5 neue MCP-Tools + Docs + Landing-Section. Wartung danach: ~2-3h/Monat
plus weitere SDKs nach Demand (Python, Go).

### Reihenfolge (mein Vorschlag)

1. Web-Analytics-MVP polieren (OAuth, Distribution, erste 50 zahlende User)
2. **Dann** MCP-Server-Analytics als 2. Säule
3. Show HN Reload mit dickerem Story: "we're building the analytics layer
   for the MCP ecosystem"

### Risiken

- Markt klein heute (~1000 öffentliche MCP-Server, davon vielleicht 50
  kommerziell ernsthaft). Free-Tier wäre Standard, Paid-Conversion niedrig.
- Enterprise-MCPs (Notion, Slack, Linear) haben eigene Analytics → Indie-Pond.
- Multi-Sprache-SDK-Wartung skaliert nicht-linear.

---

### Klares NICHT-Versprechen

Auch mit allen 4 Phasen können wir niemals sagen:
- *„Ein Mensch hat ChatGPT nach dir gefragt"* — wir sehen den HTTP-Fetch,
  nicht den Chat-Kontext drumherum
- *„Cross-Site-AI-Tracking"* — Cookies sind per Domain, das geht prinzipiell
  nicht ohne Fingerprinting (was wir bewusst nicht machen)
- *„Welche Frage der User wirklich gestellt hat"* — nur die URL die gefetched
  wurde
- *„Zero Maintenance"* — neue AI-Agenten launchen monatlich, IP-Ranges
  shiften, UA-Patterns brauchen Updates. ~1-2h/Monat dauerhaft.

---

## CHANGELOG (Working Doc)

- **2026-05-07** — Bot-Phase 2 (Cloudflare-Taxonomie) deployed. Neuer
  Go-Package `ingestion/internal/classify` mit 8-Klassen-Klassifikation
  (`user / ai_user_action / ai_search / ai_training / search_index /
  social_unfurl / scanner / bot_other`). Kombiniert UA-Pattern-Matching
  (~70 Einträge), IP-CIDR-Trie (refresh alle 6h aus
  OpenAI/Google/Bing/AWS/GCP/CF JSONs, atomic-swap, MinShrinkRatio-
  Sanity-Check, Embedded-Fallback fürs Cold-Start), FCrDNS-Reverse-DNS
  für Anthropic, und eine Generic-Browser-from-Cloud-Heuristik.
  MCP-Tools `top_user_agents` + `traffic_class_breakdown` exposen
  alle 8 Klassen mit `humans`-Filter-Alias (= `user + ai_user_action`).
  Retroactive Migration via `cmd/reclassify`. Daily Live-Source-
  Schema-Check via neuer GH-Action (Out-of-Band-Detector für
  Endpoint-Drifts wie Google's March-2026-URL-Move). CI-Workflow
  re-enabled (war seit 2026-04-23 deaktiviert).
- **2026-05-07** — BRIEFING.md aufgeräumt: Status-Dashboard auf
  tatsächlichen Code-Stand gebracht (Deployment + OAuth + Bot-Phase 1
  + Pricing-Strategie alles `[DONE]`), P0-Section komplett entfernt
  (alles done), P1 auf 3 echte Reste reduziert (CI, Email-Blacklist,
  Uptime-Monitoring), Erfolgskriterien-Checkboxen ehrlich abgehakt,
  ZEITSCHÄTZUNG-Tabelle durch tatsächliche Phasen-Timeline ersetzt.
- **2026-05-07** — Pricing-Strategie finalisiert + Landing-Page-Section
  live: 3-Tier-Modell (Free 100k / Pro €19 / Enterprise ab €299) mit
  €1/1M Hits Overage, kein Annual, keine Team-Seats, MCP-Server-Pillar
  als 2. Säule für später geparkt. Recherche von 3 Subagent-Pässen +
  kritischer Bewertung in `PRICING.md` (300+ Zeilen mit Konkurrenzmatrix,
  COGS-Rechnung, Roadmap-Mapping, Adoption-Estimate). Pricing-Section
  auf Landing-Page brutalist mit 3-Zonen-Layout, hover-Tooltips für
  unshipped Pro-Features ("very soon"/"soon"/"soon-ish").
- **2026-05-05** — OAuth-Hardening Block 2: `/settings` als enge,
  Session-basierte UI für OAuth-Connector-Management wieder eingeführt
  (anders als die 2026-04-25 entfernte Variante: nur Cookie-Session,
  nur für die Settings-Seite, NICHT für die MCP-API). Sliding 30-min
  Idle, Sign-In via Verify-Link-Klick, Sign-Out bumpt
  `users.session_version` um Cookie-Replay zu blocken. Pinned
  Cookie-Flags (`secure`, `httponly`, `same_site: :lax`).
- **2026-05-05** — OAuth-Hardening Block 1: Revocation-Endpoint
  (RFC 7009), Audit-Log (append-only), Rate-Limits auf alle OAuth-
  Endpoints, `trusted_proxies` gegen XFF-Spoofing, User-Deletion-
  Cascade, DCR-Field-Caps. Discovery advertiset jetzt
  `revocation_endpoint`, `resource_parameter_supported` (RFC 8707),
  `op_policy_uri` + `op_tos_uri`.
- **2026-05-02** — OAuth Phase 2 Foundation: Authorization-Code-Flow
  mit PKCE, Dynamic Client Registration, RFC 8707 Resource Indicators,
  Two-Scope-Modell (`analytics:read` + `analytics:manage`) mit
  Tool-Level-Enforcement, `regenerate_api_token` für OAuth-Sessions
  versteckt.
- **2026-04-23** — Initial scaffold (Week 1–4 Output) eingecheckt.
  CI vorerst deaktiviert (keine Tests). Dieses Working Doc angelegt.
- **2026-04-27** — Bot- und AI-Agent-Klassifikation Phase 1 deployed:
  `traffic_class` + `user_agent` Spalten in `events`, Default-Queries
  filtern jetzt nach `user`, neue MCP-Tools `top_user_agents` und
  `traffic_class_breakdown`. Phase 2 (Crawl-Purpose Taxonomie),
  Phase 3 (Web Bot Auth Signaturen) und Phase 4 (Server-side Hybrid
  Tracking via Middleware) als detaillierte Roadmap im Briefing
  dokumentiert. State-of-the-Art Recherche eingeflossen (Cloudflare
  AI Crawl Control, DataDome, Web Bot Auth IETF). Phase 4 (Middleware-
  Gem) als „Biggest Unlock" markiert — schließt die JS-Tracker-blind-
  spot-Lücke (Bots die kein JS rendern).
- **2026-04-26** — Landing-Page-Sweep: Brand-Sicherheit von
  `info@spreenovate.de` auf `info@mcp-analytics.com` (nur Site, nicht
  Operator-Alerts), `/terms` + `/privacy` mit `noindex,nofollow`,
  alle Outbound-Links zu Legal-Pages mit `rel=nofollow`.
- **2026-04-25** — Drop /login + /settings + magic_link Stack komplett.
  Token-Recovery jetzt via Idempotent-Re-Signup über die Landing-Form.
  /terms (mit Imprint § 5 TMG) + /privacy (GDPR) brutalist gebaut.
  `get_started_guide` jetzt auch in AUTHENTICATED Tool-Liste.
- **2026-04-24** — Brutalist Landing-Page (v4) live, Email-Signup-Form
  via SignupsController + Signup Service (shared mit MCP register_account).
  Click-to-Copy auf Verify-Page. v1-v4 Mockups in `mockups/` archiviert.
- **2026-04-24** — OAuth-Roadmap (Phase 2) ins Briefing aufgenommen.
  Variante B (Consent-Screen nach Magic-Link-Login) als Zielarchitektur
  festgelegt. Implementierung erst nach Deploy + Dogfooding.
- **2026-04-23** — Garbage-Site-IP-Block:
  - Neues Go-Paket `ingestion/internal/ipblock` (sliding window, threshold 100
    unique unknown site_ids per IP per hour → 1h block)
  - `abuse_events` Tabelle, Go schreibt Alert-Row bei Block
  - `OperatorMailer.abuse_alert` + `AbuseAlertJob` bündelt pending Events
    alle 5 Min zu einer Digest-Mail
- **2026-04-23** — Fixes + Tests:
  - Atomic UPSERTs in `UsageCounter` und `UnknownSiteHit`
  - Rate-Limits für `register_account` (3/IP/h, 10/IP/d, 5/Domain/d) und
    `magic_link` (5/Email/h) via neuem `RateLimit` Service
  - 88 Rails-Tests (Models, MCP Tools & Controller, Verify, Sessions, Settings)
  - 41 Go-Tests (bot, session, ratelimit, usage, ua, config, sites, ch, server)
  - Bug gefixt: iPhone-UAs wurden als macOS erkannt, weil „like Mac OS X"
    vor dem iPhone-Check matcht — Reihenfolge in `ua.Parse` korrigiert
