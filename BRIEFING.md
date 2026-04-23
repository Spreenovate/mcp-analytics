# PROJEKT: mcp-analytics — Working Document

Stand: 2026-04-23 · Branch: `main` · Tests: 88 Rails + 41 Go = 129, alle grün

Dieses Dokument ist der ursprüngliche Briefing-Text, annotiert mit dem
aktuellen Umsetzungsstand. Originaltext ist unverändert; Status-Blöcke und
Notizen sind eingefügt.

Legende:

- `[DONE]`     — umgesetzt
- `[PARTIAL]`  — teilweise, Detail im Hinweis
- `[TODO]`     — noch offen
- `[SKIP]`     — bewusst aus MVP ausgeschlossen

---

## STATUS-DASHBOARD

| Bereich                              | Status       | Hinweis                                                          |
|--------------------------------------|--------------|------------------------------------------------------------------|
| Infrastruktur / Kamal-Setup          | `[PARTIAL]`  | `config/deploy.yml` + `.kamal/secrets` existieren; Host-IP ist `1.2.3.4`, noch nie deployt |
| Rails-App Gerüst (Rails 8 + SQLite)  | `[DONE]`     | Gemfile, Dockerfile, config, routes, Solid Queue in Puma         |
| Datenmodell Rails (6 Tabellen)       | `[DONE]`     | Alle Migrations + Models vorhanden                               |
| Datenmodell ClickHouse               | `[DONE]`     | `events` + `events_hourly` + `referrers_daily` MVs               |
| Go-Ingestion-Service                 | `[DONE]`     | Bot-Filter, Rate-Limit, Salt-Hashing, Usage-Buffer, Site-Cache   |
| Tracking-Script                      | `[DONE]`     | `ingestion/static/script.js` (131 Zeilen)                        |
| MCP-Server + alle 18 Tools           | `[DONE]`     | JSON-RPC in `app/services/mcp/`                                  |
| MCP-Auth-Recherche                   | `[DONE]`     | Entschieden: Bearer-Header + `?token=` Fallback, kein OAuth      |
| Web-UI (Landing, Verify, Settings)   | `[DONE]`     | Alle Views + Controller                                          |
| Signup-/Verify-Flow inkl. Mails      | `[DONE]`     | VerificationMailer, MagicLinkMailer                              |
| Recurring Jobs (Salt, Purge, Usage)  | `[DONE]`     | `config/recurring.yml` + 3 Job-Klassen                           |
| Anti-Abuse (Rate-Limits, komplett)   | `[DONE]`     | /event, MCP 60/min, `register_account` 3/IP/h + 10/IP/d + 5/Dom/d, `magic_link` 5/Email/h |
| Anti-Abuse (Garbage-Site-IP-Block)   | `[TODO]`     | `unknown_site_hits` wird geschrieben, aber kein IP-Block + Alert |
| Concurrency (Atomic UPSERTs)         | `[DONE]`     | `UsageCounter`, `UnknownSiteHit` → `INSERT ... ON CONFLICT`      |
| Email-Blacklist für Trash-Domains    | `[PARTIAL]`  | Logik in `Tools#disposable_email_domain?` — Liste prüfen/pflegen |
| Backup-Script                        | `[DONE]`     | `ops/backup.sh` (täglich, SQLite + ClickHouse)                   |
| Monitoring / Alerts                  | `[PARTIAL]`  | Usage-Alert per Mail; Uptime/Disk/Garbage-Pattern noch offen     |
| Tests Rails (88)                     | `[DONE]`     | Models, MCP Tools, MCP Controller, Verify, Sessions/Settings     |
| Tests Go (41 über 9 Pakete)          | `[DONE]`     | bot, session, ratelimit, usage, ua, config, sites, ch, server    |
| Deployment auf Hetzner               | `[TODO]`     | Server aufsetzen, Secrets, DNS, `kamal setup`                    |
| Dogfooding retreaturlaub / triageflow| `[TODO]`     | Erst nach Deploy                                                 |

**Kritischer Pfad bis Launch**: ~~Tests~~ ✅ → echter Hetzner-Host + DNS →
`kamal setup` + erste Deploy → Dogfooding → Garbage-Pattern-Alert.

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

## INFRASTRUKTUR  — `[PARTIAL]`

- 1 Server: Hetzner CX32 (4 vCPU, 8GB RAM, 80GB SSD), Standort Falkenstein
- ClickHouse läuft direkt auf der Server-SSD unter /var/lib/clickhouse
  (kein separates Volume im MVP – kann später ohne Code-Änderung migriert
  werden)
- Tägliche automatische Backups
- Domain: mcp-analytics.com
- Deployment: Kamal 2, alles als Docker-Container
- Reverse Proxy / TLS: kamal-proxy (kein nginx separat)
- Let's Encrypt automatisch via kamal-proxy

> **Status**: `config/deploy.yml` und `.kamal/secrets` sind eingecheckt.
> Host-IP ist noch Platzhalter `1.2.3.4`, Server nicht bestellt, DNS nicht
> gesetzt, `kamal setup` nie gelaufen. Backup-Script liegt unter
> `ops/backup.sh`.
>
> **TODOs**:
> - Hetzner CX32 in Falkenstein bestellen, IP in `config/deploy.yml`
>   (Rollen `web` und `ingest`) eintragen
> - DNS A-Records für `mcp-analytics.com` und `t.mcp-analytics.com`
> - Secrets in `.kamal/secrets` befüllen (`RAILS_MASTER_KEY`,
>   `KAMAL_REGISTRY_PASSWORD`, `SMTP_USERNAME`/`PASSWORD`,
>   `CLICKHOUSE_PASSWORD`)
> - `kamal setup` + erste `kamal deploy`
> - Cronjob für `ops/backup.sh` auf dem Host einrichten

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

> **Entscheidung**: Bearer-Header als primärer Weg, `?token=` als Fallback
> (für Clients, die keinen Custom-Header setzen können). Implementiert in
> `app/controllers/mcp_controller.rb` (`authenticate_from_request`).
> OAuth ist für Post-MVP vorgesehen, nicht blockierend.

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
- UA-Blacklist beim Ingest (filtert ~80%)
- Headless-Browser-Marker im Tracking-Script vorab filtern
  (navigator.webdriver, etc.)
- Heuristik in ClickHouse-Aggregation: Sessions mit >5 Events/Sek
  werden in Materialized Views nicht gezählt (markiert, nicht gelöscht)

> **Status**: Alle Schritte 1–11 umgesetzt in
> `ingestion/internal/server/server.go` + Packages `bot`, `ratelimit`,
> `session`, `ua`, `ch`, `usage`, `sites`.
>
> **Offen bestätigen**: Heuristik "Sessions mit >5 Events/Sek werden in
> MVs nicht gezählt" — ist so nicht in den MVs implementiert. Prüfen, ob
> das vor Launch gebraucht wird oder Post-MVP reicht.

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

## ANTI-ABUSE  — `[PARTIAL]`

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

> **Status**:
> - `[DONE]`  60/min MCP-Queries (`McpRateBucket`)
> - `[DONE]`  100 Events/s per site_id (`ingestion/internal/ratelimit`)
> - `[DONE]`  Free-Tier-Alert via `UsageLimitAlertJob`
> - `[DONE]`  `unknown_site_hits` werden geschrieben
> - `[PARTIAL]` Email-Blacklist: `disposable_email_domain?` prüft, Liste
>              sollte mit einer aktuellen GitHub-Liste gegengecheckt werden
> - `[TODO]`  Rate-Limits `register_account` (3/IP/h, 10/IP/d,
>              5/Domain/d) und `magic_link` (5/Email/h) und `add_site`
>              (10/User/d) — Implementation im Controller prüfen
> - `[TODO]`  IP-Block (1h) bei >100 Garbage-Site-IDs/IP/h
> - `[TODO]`  Operator-Mail bei wiederholtem Garbage-Pattern

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

## ROADMAP NACH MVP (NICHT TEIL DIESES BRIEFINGS)

Phase 2: MaxMind Geo-Lookup, Stripe-Integration, Pricing-Tiers
Phase 3: Enterprise-Tier mit dedicated Servern, query_sql, SLA
Phase 4: Team-Accounts, Connector-Directory-Eintrag, Self-Hosted Script,
         eventuell minimales Dashboard für Power-User

## ERFOLGSKRITERIEN MVP

Funktional:
- [ ] Tracking-Snippet einbinden → Events landen in ClickHouse
- [ ] Über MCP in Claude → Daten kommen zurück
- [ ] Signup-Flow funktioniert end-to-end inkl. Pre-Verify-Tracking
- [ ] Mehrere Sites parallel ohne Daten-Leak
- [ ] 3 Privacy-Modi sauber implementiert
- [ ] Garbage-Events gegen unbekannte Site-IDs failed silent

Performance:
- [ ] Ingestion <50ms p99 (Response-Zeit, Storage-Wartezeit async)
- [ ] MCP-Query <500ms p95 für Standard-Tools
- [ ] 100 aktive Sites parallel auf einem CX32 ohne Probleme

Operational:
- [ ] Kamal-Deploy in <2 Min
- [ ] Backup automatisiert (täglich, mindestens SQLite + ClickHouse-Tables)
- [ ] Monitoring: Uptime-Check, Disk-Alert, Garbage-Site-Hit-Alert,
              Free-Tier-Überschreitungs-Alert

> **Status**: Noch keines dieser Kriterien live verifiziert — erst nach
> erstem Deploy + Dogfooding messbar. Checkboxen bewusst leer.

## ZEITSCHÄTZUNG (4–6 Wochen laut Original-Briefing)

| Woche | Thema                                                           | Status       |
|-------|-----------------------------------------------------------------|--------------|
| 1     | Infrastruktur, Tracking-Script, Ingestion-Endpoint              | `[DONE]`     |
| 2     | ClickHouse-Schema, Materialized Views, Analytics-Queries        | `[DONE]`     |
| 3     | MCP-Server (Tools, Auth, Rate-Limits), Site-Management          | `[DONE]`     |
| 4     | Signup-Flow, Verify-Page, Settings, Landing                     | `[DONE]`     |
| 5–6   | Dogfooding (retreaturlaub.de + triageflow.com), Bugfixes, Launch| `[TODO]`     |

---

## OPEN ACTIONS (priorisiert)

### P0 — Blocker vor Live-Launch

1. **Hetzner CX32 bestellen** (Falkenstein)
2. **DNS setzen**: `mcp-analytics.com` + `t.mcp-analytics.com` → Server-IP
3. **`config/deploy.yml`**: Platzhalter-IPs `1.2.3.4` in `web`/`ingest`
   ersetzen
4. **`.kamal/secrets`** befüllen: `RAILS_MASTER_KEY`,
   `KAMAL_REGISTRY_PASSWORD`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
   `CLICKHOUSE_PASSWORD`
5. **`kamal setup`** + erster `kamal deploy`
6. **Backup-Cron** auf Host (täglich `ops/backup.sh`)
7. **Smoke-Test End-to-End**: `register_account` → Mail → `/verify`
   → `add_site` → Tracking-Snippet auf Test-Seite → Event in ClickHouse
   → `get_overview` via Claude

### P1 — Vor Dogfooding / Marketing

8. ~~**Tests schreiben**~~ ✅ erledigt: 129 Tests (88 Rails + 41 Go), grün.
9. ~~**Anti-Abuse Rate-Limits** für `register_account`, `magic_link`~~ ✅
   erledigt (`app/services/rate_limit.rb` + `Tools#enforce_register_rate_limits!`
   + `SessionsController#create`). `add_site` war schon da.
10. **Garbage-Site-ID → IP-Block (1h)** in Go implementieren, plus
    Operator-Alert-Mail bei Pattern
11. **Email-Domain-Blacklist** gegen aktuelle GitHub-Liste aktualisieren
12. **Monitoring**: Uptime-Check (UptimeRobot / simpler Cron), Disk-Alert
    (`df`-Warnung bei >80%)

### P2 — Nach erstem Launch

13. **Dogfooding** retreaturlaub.de + triageflow.com — Tracker einbauen,
    eigene Daten per Claude abfragen
14. **Bot-Heuristik in MVs**: Sessions mit >5 Events/s ausklammern
    (laut Briefing; derzeit nicht in MVs)
15. **Landing Copy + Demo-Video** (wenn UI-Ready)
16. **CI wieder einschalten**, sobald Tests existieren
    (Workflow `.github/workflows/ci.yml` wurde am 2026-04-23 gelöscht)

### Offene Detail-Fragen (im Code zu klären)

- Tracking-Script-URL: Briefing sagt `mcp-analytics.com/script.js`, Code
  liefert unter `t.mcp-analytics.com/script.js`. Marketing/Snippet
  entsprechend. **Entscheidung dokumentieren** bevor man anfängt nach
  außen zu kommunizieren.

---

## CHANGELOG (Working Doc)

- **2026-04-23** — Initial scaffold (Week 1–4 Output) eingecheckt.
  CI vorerst deaktiviert (keine Tests). Dieses Working Doc angelegt.
- **2026-04-23** — Fixes + Tests:
  - Atomic UPSERTs in `UsageCounter` und `UnknownSiteHit`
  - Rate-Limits für `register_account` (3/IP/h, 10/IP/d, 5/Domain/d) und
    `magic_link` (5/Email/h) via neuem `RateLimit` Service
  - 88 Rails-Tests (Models, MCP Tools & Controller, Verify, Sessions, Settings)
  - 41 Go-Tests (bot, session, ratelimit, usage, ua, config, sites, ch, server)
  - Bug gefixt: iPhone-UAs wurden als macOS erkannt, weil „like Mac OS X"
    vor dem iPhone-Check matcht — Reihenfolge in `ua.Parse` korrigiert
