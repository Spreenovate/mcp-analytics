PROJEKT: mcp-analytics

ZIEL
Web-Analytics-Tool, das ausschließlich über das Model Context Protocol (MCP)
bedient wird – kein Dashboard, keine UI für die Analytics selbst. Nutzer
greifen via Claude/ChatGPT/anderer MCP-Clients auf ihre Analytics-Daten zu.
Erste Version: MVP zum Validieren der Idee, kostenlos bis 100k Hits/Monat,
keine Bezahlfunktion, keine Enterprise-Features.

POSITIONIERUNG
"Analytics für deinen AI-Workflow. Frag deine Daten, statt durch Dashboards
zu klicken." Bonus-Argumente: keine Tabs, Custom Events first-class,
GDPR-easy (EU-Hosting auf Hetzner Falkenstein), kein Cookie-Banner nötig
im Strict-Modus.

TARGET USER
Indie SaaS Founder, Bloggers, Newsletter-Operators, Side-Project-Bauer.
Leute, die Claude oder vergleichbare AI-Tools täglich nutzen und ihre
Analytics nicht in einem separaten Tool haben wollen.

INFRASTRUKTUR
- 1 Server: Hetzner CX32 (4 vCPU, 8GB RAM, 80GB SSD), Standort Falkenstein
- ClickHouse läuft direkt auf der Server-SSD unter /var/lib/clickhouse
  (kein separates Volume im MVP – kann später ohne Code-Änderung migriert
  werden)
- Tägliche automatische Backups
- Domain: mcp-analytics.com
- Deployment: Kamal 2, alles als Docker-Container
- Reverse Proxy / TLS: kamal-proxy (kein nginx separat)
- Let's Encrypt automatisch via kamal-proxy

STACK
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

OFFENE TECHNISCHE FRAGE (RECHERCHE NÖTIG VOR IMPLEMENTATION)
Welcher Auth-Mechanismus für Remote-MCP-Server ist der korrekte Weg
in 2026? Optionen:
- URL-Query-Param-Token (?token=xxx) – funktioniert, aber unschön
- Bearer-Token im Authorization-Header – sauberer
- OAuth 2.0 Authorization Code Flow – Anthropic-empfohlen, aber komplex
Vor Implementation in der aktuellen Anthropic-Doku zu Remote MCP Servern
nachlesen und passende Variante wählen. Empfehlung als Default:
Bearer-Token im Header, falls OAuth-Setup zu aufwändig für MVP.

DATENMODELL: Rails (SQLite)

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

DATENMODELL: ClickHouse

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

PRIVACY MODES (per Site bei add_site() gewählt, NICHT änderbar)

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

TRACKING-SCRIPT (~50-80 Zeilen Vanilla JS)

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

INGESTION-FLOW

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

MCP-SERVER

EINE MCP-URL für alles, mit Conditional Tools je nach Auth-Status:

URL: https://mcp-analytics.com/mcp
- Ohne Auth-Token: zeigt nur Signup-Tools
- Mit Auth-Token (über Bearer-Header oder Query-Param, je nach
  Recherche-Ergebnis): zeigt Analytics-Tools

Das hat den Vorteil, dass der User nur EINE Connector-URL hinzufügen
muss und sie später nur um den Token-Param erweitert.

UNAUTHENTICATED TOOLS (Signup-Phase)

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

AUTHENTICATED TOOLS (mit Token)

list_sites()
  → [{site_id, domain, privacy_mode, hits_this_month, plan_limit,
      created_at}]

add_site(domain: string, 
         privacy_mode: 'strict'|'default'|'all' = 'strict')
  → {
      site_id: "tb_8x9k2m4n",
      tracking_snippet: "<script defer data-site=\"tb_8x9k2m4n\" ...",
      install_instructions: "Falls du schon mit Platzhalter gearbeitet
        hast: einmal in deinem Codebase suchen+ersetzen
        DUMMY_SITE_ID_REPLACE_AFTER_VERIFY → tb_8x9k2m4n"
    }
  → Rate-Limit: 10 pro User/Tag

get_tracking_snippet(site_id: string)
  → {snippet_html, install_instructions}

remove_site(site_id: string)
  → soft-delete, ClickHouse-Daten bleiben TTL-lang erhalten

get_overview(site_id: string, period: string = 'last_7_days')
  → {pageviews, unique_visitors, sessions, bounce_rate, 
     avg_session_duration}
  → period-Format: 'today', 'yesterday', 'last_7_days', 'last_30_days',
                   'last_90_days', 'last_12_months', 
                   'YYYY-MM-DD..YYYY-MM-DD'

get_timeseries(site_id, 
               metric: 'pageviews'|'visitors'|'sessions',
               period, 
               granularity: 'hour'|'day'|'week' = 'day')
  → [{timestamp, value}]

top_pages(site_id, period, limit: int = 10)
  → [{url_path, pageviews, unique_visitors}]

top_referrers(site_id, period, limit: int = 10)
  → [{referrer_host, visits, percentage_of_total}]

top_sources(site_id, period, limit: int = 10)
  → [{utm_source, utm_medium, utm_campaign, visits}]

breakdown(site_id, 
          dimension: 'browser'|'os'|'device_type'|'country',
          period, 
          limit: int = 10)
  → [{value, visits, percentage}]
  → 'country' im MVP: liefert leere Liste oder Hinweis "Geo nicht
    aktiviert"

list_events(site_id, period)
  → [{event_name, count, unique_sessions}]
  → enthält 'pageview' und alle Custom Events

event_details(site_id, event_name, period, group_by_property: string?)
  → wenn group_by gesetzt: [{property_value, count}]
    sonst: {total_count, top_pages_with_event, sessions_with_event}

compare_periods(site_id, metric, period_a, period_b)
  → {a_value, b_value, absolute_change, percent_change}

get_account()
  → {email, plan, total_sites, total_hits_this_month, plan_limit,
     api_token_first_chars}

regenerate_api_token()
  → invalidates old token, returns new token + new MCP-URL

Auth-Layer: Token aus Header oder Query-Param lesen (siehe offene
Recherche-Frage), User finden, alle Queries automatisch nach
user.sites scopen. Kein Cross-Tenant-Zugriff möglich.

Rate-Limit MCP-Auth-Tools: 60 requests/min pro User.

EXPLIZIT NICHT ENTHALTEN: query_sql oder andere Power-User-Tools.
Diese sind als Enterprise-Offramp reserviert (siehe ENTERPRISE).

REGISTRIERUNGS-FLOW (END-TO-END)

Idealer Flow im Chat:

1. User in Claude (irgendeine Session, ohne mcp-analytics-Connector):
   "Bau mir eine Tierbilder-Seite und nutze mcp-analytics für Tracking"

2. Claude: "Dafür brauche ich einmalig den mcp-analytics Connector.
   Füg bitte hinzu: https://mcp-analytics.com/mcp – das ist öffentlich
   und braucht erstmal kein Token. Sag Bescheid wenn drin."

3. User aktiviert Connector für die Session.

4. Claude ruft register_account(email) auf, bekommt pending_user_id
   und Platzhalter-ID zurück.

5. Claude baut die komplette Seite mit dem Platzhalter
   DUMMY_SITE_ID_REPLACE_AFTER_VERIFY als data-site.

6. Claude: "Seite fertig. Schau in deine Mail und klick den
   Bestätigungslink. Auf der Seite siehst du dein Token + neue MCP-URL.
   Update den Connector damit, dann melden wir die Site final an."

7. User klickt Mail-Link → /verify/<token> → Verify-Page zeigt:
   - "✓ Email bestätigt"
   - API-Token (Copy-Button)
   - Neue MCP-URL: https://mcp-analytics.com/mcp?token=<token>
     (oder Anleitung Bearer-Header, je nach Recherche)
   - Anleitung: Connector-URL aktualisieren

8. User aktualisiert Connector-URL, kommt zurück: "Drin"

9. Claude ruft list_sites() auf (leer), dann 
   add_site("tierbilder.de", privacy_mode="strict"), bekommt echte
   site_id.

10. Claude: "Perfekt, deine Site-ID ist tb_8x9k2m4n. Einmal in deinem
    Codebase suchen+ersetzen: DUMMY_SITE_ID_REPLACE_AFTER_VERIFY →
    tb_8x9k2m4n. Dann ist alles live."

11. Done.

WEB-UI (MINIMAL)

GET /
  Landing-Page (statisch). Erklärung des Konzepts, MCP-URL zum
  Hinzufügen, Demo-Video. Kein Web-Signup-Formular.

GET /verify/:token
  Verifiziert Token, erstellt User, generiert API-Token.
  Zeigt: API-Token + MCP-URL + Anleitung Connector-Update.
  Diese Seite ist der EINZIGE Zwangs-Touchpoint im Browser.

GET /settings (Auth via Magic Link)
  - Email anzeigen
  - API-Token anzeigen + regenerieren
  - Sites listen mit Hits this month
  - Account löschen

POST /magic-link
  Sendet Login-Link für /settings an die hinterlegte Email.
  Token 15 min gültig.

KEINE Analytics-UI. Datenansicht ausschließlich über MCP.

ANTI-ABUSE

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

ENTERPRISE-OFFRAMP

Wenn User mehr will (höhere Limits, query_sql, dedicated Server, SLA,
Geo-Daten, Custom Domain für Tracking):
Verweis auf Kontaktformular / Email an enterprise@mcp-analytics.com.
Manueller Sales-Prozess, nicht im MVP automatisiert.

EXPLIZIT NICHT IM MVP

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

ROADMAP NACH MVP (NICHT TEIL DIESES BRIEFINGS)

Phase 2: MaxMind Geo-Lookup, Stripe-Integration, Pricing-Tiers
Phase 3: Enterprise-Tier mit dedicated Servern, query_sql, SLA
Phase 4: Team-Accounts, Connector-Directory-Eintrag, Self-Hosted Script,
         eventuell minimales Dashboard für Power-User

ERFOLGSKRITERIEN MVP

Funktional:
- Tracking-Snippet einbinden → Events landen in ClickHouse
- Über MCP in Claude → Daten kommen zurück
- Signup-Flow funktioniert end-to-end inkl. Pre-Verify-Tracking
- Mehrere Sites parallel ohne Daten-Leak
- 3 Privacy-Modi sauber implementiert
- Garbage-Events gegen unbekannte Site-IDs failed silent

Performance:
- Ingestion <50ms p99 (Response-Zeit, Storage-Wartezeit async)
- MCP-Query <500ms p95 für Standard-Tools
- 100 aktive Sites parallel auf einem CX32 ohne Probleme

Operational:
- Kamal-Deploy in <2 Min
- Backup automatisiert (täglich, mindestens SQLite + ClickHouse-Tables)
- Monitoring: Uptime-Check, Disk-Alert, Garbage-Site-Hit-Alert,
              Free-Tier-Überschreitungs-Alert

ZEITSCHÄTZUNG

4-6 Wochen für eine technisch erfahrene Person mit Rails-Background.
- Woche 1: Infrastruktur (Hetzner, Kamal, Container-Setup), 
           Tracking-Script, Ingestion-Endpoint
- Woche 2: ClickHouse-Schema, Materialized Views, Analytics-Queries
- Woche 3: MCP-Server (Tools, Auth, Rate-Limits), 
           Site-Management
- Woche 4: Signup-Flow (register_account, Verify-Page), 
           Settings, Landing
- Woche 5-6: Dogfooding (Tracking auf retreaturlaub.de + 
             triageflow.com integrieren), Bugfixes, 
             Anti-Abuse-Tuning, Launch-Vorbereitung