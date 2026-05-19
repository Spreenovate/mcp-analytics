# CONTENT_MARKETING.md — On-Site Content-Strategie

Working-Doc neben `BRIEFING.md` und `PRICING.md`. Fokus: **alles On-Page**
(eigene Domain `mcp-analytics.com`, kein Reddit-/Twitter-/Newsletter-Spiel
in diesem Dokument — das gehört in eine separate Distribution-Strategie).

Stand: 2026-05-19 · Single-Founder, Pre-Revenue, MCP-Directory-Listing
ist der harte Acquisition-Funnel.

---

## TL;DR

1. **Wedge schärfen**: Niemand sonst kommerziell MCP-native. Der gesamte
   Content muss diesen Wedge bedienen, nicht "noch ein Plausible-Blog"
   sein.
2. **Drei Content-Säulen** (in der Reihenfolge ihrer Acquisition-Power):
   **(a)** MCP/AI-Workflow-Tutorials, **(b)** ehrliche Privacy/GDPR-Vergleiche,
   **(c)** Bot-/AI-Crawler-Beobachtungen (live-Daten aus eigenem Ingest).
3. **Programmatic SEO** auf zwei Achsen: `/vs/{plausible|fathom|pirsch|umami|posthog}`
   (Bottom-of-Funnel) und `/mcp/{tool-name}` (Awareness — "Wie sieht
   `top_referrers` aus, wenn ich Claude frage?").
4. **Live-Daten als Content-Moat**: ein wöchentliches public
   "AI-Crawler-Index"-Update (welche Crawler hits/Mo, welche Sites werden
   am meisten von ChatGPT/Perplexity referenced) — niemand sonst kann das
   aus *Origin*-Daten zeigen (CF kann es, will es aber nicht öffentlich
   für Non-Kunden tun).
5. **Cadence realistisch für Single-Founder**: 1 Cornerstone-Piece/Monat
   + 4 Programmatic-Pages/Woche (templated) + 1 Crawler-Report/Woche
   (semi-automatisiert aus eigenen ClickHouse-Daten).
6. **Erfolgsmessung dogfooded**: mcp-analytics trackt mcp-analytics.com.
   KPIs werden via Claude abgefragt — der Founder *ist* die erste
   Demo-Page (siehe `BRIEFING.md` Dogfooding-Followup).

---

## 1. Strategische Basis

### 1.1 Was uns von "normalen" SaaS-Blogs unterscheidet

Wir haben **kein Dashboard** und damit auch keinen "Schau-mal-wie-cool-
unser-Produkt-aussieht"-Content. Jeder Screenshot wäre ein Chat-Verlauf
mit Claude. Das ist eine Stärke, keine Schwäche:

- **Chat-Logs sind besseres Content-Material als Dashboard-Screenshots.**
  Sie zeigen *Intent → Antwort* statt *UI-Krempel*. Lassen sich nativ
  in Markdown rendern, sind copy-pasteable, ranken in
  ChatGPT-Antworten/Perplexity-Citations besser (weil bereits im
  Frage-Antwort-Format).
- **AI-Suchmaschinen lieben Q&A-Struktur.** Unsere Inhalte sollten
  *Fragen* sein, die ein Nutzer einem Agenten stellt, gefolgt von
  der wörtlichen Agenten-Antwort + Erklärung der MCP-Tools, die er
  verwendet hat.

### 1.2 Zielgruppen-Personas (aus BRIEFING.md verfeinert)

| Persona | Wo sie sind | Pain | Hook | Cornerstone-Content |
|---|---|---|---|---|
| **Indie SaaS Founder "Tom"** | bauen mit Claude Code, Cursor, deployed via Vercel/Fly | "Ich will Stats checken ohne den Flow zu unterbrechen" | "Frag deine Analytics in Cursor" | `/blog/analytics-in-cursor` |
| **AI-Power-User Newsletter-Operator "Lena"** | Ghost/Beehiiv, schreibt täglich, eine Hand am Claude-Chat | "Welche Posts werden gerade von ChatGPT zitiert?" | AI-Referrer-Tracking (default-mode hat `referrer_host`) | `/blog/who-cites-your-newsletter` |
| **Privacy-conscious Solo-Dev "Janek"** | Plausible-Nutzer, EU, GDPR-allergisch | "Plausible-Banner nervt, EU-Hosting brauche ich" | Strict-Mode = no cookie, kein Banner | `/vs/plausible` + `/blog/no-cookie-banner` |
| **Bot-/Abuse-paranoide Side-Project-Bauer "Markus"** | Side-Project hat einen Spike, will wissen ob Mensch oder Crawler | Cloudflare zeigt's nur CF-Kunden | `traffic_class_breakdown` MCP-Tool | `/ai-crawler-index` (live) |

**Wer ist NICHT die Zielgruppe** (und damit kein Content-Aufwand):
Enterprise-Marketing-Teams, GA4-Migranten, e-Commerce Conversion-Optimierer,
Mobile-App-Operatoren. Solange Free-Tier kein Hub für die wird, kein
Akquise-Hebel.

### 1.3 Tonalität & Stil

Bereits etabliert im Briefing-Stil und in der Landing (`home.html.erb`):
brutalist, monospace, "show don't tell". Content-Konventionen:

- **Kein Marketing-BS.** Keine "10 Reasons Why"-Listen. Keine Floskeln
  ("supercharge your growth"). Wenn etwas nicht funktioniert, schreib
  es hin (siehe `CLAUDE.md` für unseren Umgang mit eigenen Bugs).
- **Code-First.** Jeder Artikel enthält mindestens einen lauffähigen
  Chat-Snippet oder eine Shell-Command. Wenn nicht copy-pasteable,
  nicht published.
- **Eigene Daten zitieren** wo möglich. "In der letzten Woche kamen
  43% der ChatGPT-Citations zu *X* von Domains, die …" schlägt jede
  generische Behauptung.
- **Länge**: Cornerstone 1500–2500 Wörter mit Tabellen/Snippets;
  Programmatic 400–700 Wörter; Crawler-Reports kurz (Headline,
  Tabelle, 1 Absatz Kommentar).

---

## 2. Content-Säulen

### Säule A — MCP & AI-Workflow-Tutorials (Acquisition-Top)

**Ziel**: Leute, die "Claude + Analytics" oder "MCP + irgendwas" suchen,
auf die Site holen. Diese Suchen wachsen 2026 schneller als jeder
Plausible-Vergleich.

Konkrete Pieces (Cornerstone-Format, 1500–2500 Wörter):

- **"Web Analytics in Claude Desktop einrichten — Schritt für Schritt"**
  (`/blog/claude-desktop-analytics-setup`) — Screenshots der Connector-
  Page, OAuth-Flow, erste 5 Tool-Calls. Direkter Konkurrent: keiner
  hat einen vergleichbar konkreten Setup-Guide.
- **"23 MCP-Tools, die du in mcp-analytics fragen kannst"**
  (`/blog/all-mcp-tools-explained`) — pro Tool: was es macht, Beispiel-
  Prompt, Beispiel-Antwort. Wird gleichzeitig "Documentation für
  Menschen". Verlinkt auf `/docs`.
- **"Analytics in Cursor: dein Side-Project ohne Tab-Wechsel überwachen"**
  (`/blog/analytics-in-cursor`)
- **"ChatGPT Custom Connectors: Analytics einbinden"**
  (`/blog/chatgpt-custom-connectors-analytics`) — relevant, weil
  ChatGPT Custom Connectors OAuth-only sind und wir den Flow sauber
  haben (siehe `OAUTH_BRIEFING.md`).
- **"MCP vs. Function-Calling vs. Plugins — was du wirklich brauchst"**
  (`/blog/mcp-vs-function-calling`)
- **"Eine Woche keine Analytics-UI: was ich gelernt habe"**
  (`/blog/no-dashboard-experiment`) — Founder-Story, dogfooding.
  Authentisch, schwer zu kopieren.

Programmatic (`/mcp/{tool-name}`, 1 Page pro MCP-Tool, ~400 Wörter):
Template = Tool-Beschreibung, Schema, 3 Beispiel-Prompts, Beispiel-Output
als Chat-Snippet. **Eine Page pro Tool × 23 Tools = 23 Pages**, die
in Long-Tail-Searches ("how to get top referrers from Claude analytics")
ranken können.

### Säule B — Ehrliche Privacy/Vergleiche (Acquisition-Bottom)

**Ziel**: User, die schon nach Plausible-Alternative suchen, abgreifen.
**Wichtig**: ehrlich vergleichen. Plausible hat Open-Source, wir nicht
(noch). Wenn wir lügen, brennt es zurück.

Konkrete Pieces:

- **`/vs/plausible`** — Tabelle Hits/Mo, Preise, Free, EU-Hosting,
  Cookie-Banner. **Ehrlich**: Plausible Free gibts nicht, wir haben.
  Plausible hat Dashboard, wir nicht (das ist Feature für uns, kein
  Bug). Plausible ist Open-Source, wir nicht (noch).
- **`/vs/fathom`** — Premium-UX vs. unser MCP-Wedge. Fathom ist
  Unlimited-Sites; wir auch. Fathom ist $15, wir €19 — leichter
  Premium-Anker.
- **`/vs/pirsch`** — DE-hosted vs. DE-hosted. Hier ist der Vergleich
  enger; Wedge ist klar MCP, nicht Hosting.
- **`/vs/umami-cloud`** — OSS-Halo, 1M Events free (mehr als wir).
  Honest: für reine UI-User ist Umami Cloud besser. Für MCP-User wir.
- **`/vs/posthog`** — Suite vs. Plausible-Form. PostHog ist enterprise-y,
  wir bewusst minimal.
- **`/vs/google-analytics`** — der Klassiker. Hier ist das Argument
  Privacy + EU + Cookie-Banner. Programmatic auch für
  `/vs/google-analytics-{deutsch|gdpr|cookieless}`.

Cornerstone "GDPR/Privacy"-Themen:

- **"Cookie-Banner-frei tracken: Strict-Mode erklärt"**
  (`/blog/no-cookie-banner`) — wie unser Strict-Mode arbeitet
  (Daily-Salt + Site-Salt + ip + ua → kein Cookie nötig). Vergleich zu
  GA-Consent-Mode-V2.
- **"DSGVO und Web-Analytics — was die DSK 2024 wirklich verlangt"**
  (`/blog/dsgvo-web-analytics-2024-dsk`) — auf deutsch zuerst, dann
  EN-Übersetzung. EU-Such-Volumen ist real.
- **"Schrems II, Server-Standort und EU-Hosting"**
  (`/blog/schrems-ii-eu-hosting`)

### Säule C — Bot-/AI-Crawler-Index (Moat-Content)

**Ziel**: Niemand sonst kann dieses Content-Format aus *Origin-Daten*
über *viele kleine Sites* liefern. CF kann es nur für CF-Kunden, kommerzielle
Bot-Tools sind Enterprise, Indie-Konkurrent (Promptwatch $99/Site) hat
keine Aggregat-Sicht.

**Was wir machen** (sobald wir ≥50 zahlende Pro-Kunden haben — vorher zu
wenig Daten):

- **Wöchentlicher `/ai-crawler-index`-Report** — Tabelle: welche Crawler
  (GPTBot, ClaudeBot, PerplexityBot, ByteSpider, AmazonBot, …) wie viele
  Hits pro 1k Pageviews; Trend WoW; neue Crawler. *Anonymisiert*,
  Aggregat über alle Pro-Sites — kein einzelner Kunde identifizierbar.
- **Quartals-Whitepaper** — gleiche Daten, tiefer, mit Methodik-Section.
  Eignet sich für Hacker-News-Post und Press-Pickups
  (TechCrunch hat 2025 jeden Cloudflare-Crawler-Report aufgegriffen).
- **`/ai-referrers-leaderboard`** — welche AI-Tools schicken in welchem
  Verhältnis Menschen-Traffic? `referrer_host` = chat.openai.com,
  perplexity.ai, gemini.google.com, claude.ai. Trends-Chart, aktualisiert
  weekly.

**Pre-Launch-Bridge**: bis wir 50 Pro-Kunden haben, hat der Index keine
glaubwürdige Stichprobe. Solange:

- **Eigene Site als N=1-Demo.** "Hier sind die Crawler, die *diese*
  Seite besuchen — was steckt dahinter?" (Dogfooding, siehe `BRIEFING.md`
  Followup.)
- **Co-Aggregation** mit zwei bis drei befreundeten Indie-Side-Projects
  (Triageflow, Retreaturlaub aus dem Briefing), die ihre Daten teilen.
  Disclaimer dranschreiben "N=4 sites, illustrative".

### Säule D — Founder-Build-in-Public-Posts (Authentizitäts-Layer)

Nicht Akquise-Säule, aber für die mit Säule A/B/C gewonnenen Visitors
ein Trust-Signal. Wenn jemand `/blog` öffnet und nur Marketing-Floskeln
sieht, springen sie ab. Wenn der zweite Artikel oben "Why I shipped a
broken `sed -u` to prod last week" heißt, bleiben sie.

- "Why mcp-analytics has no dashboard (and why I'm not building one)"
- "Building MCP OAuth — every quirk claude.ai bit me with"
  (Quelle: `CLAUDE.md`, schon dokumentiert)
- "Single-Founder, single-server, single-region — why €7.50/Mo Hetzner
  is enough" (Pricing-Spin)
- "Was 90 Tage MCP-Directory-Warteliste mich gelehrt haben"
  (sobald wir tatsächlich auf der Warteliste waren)

---

## 3. Konkrete On-Page-Struktur

```
mcp-analytics.com/
├── /                          (Landing — exists)
├── /docs                      (Human-Docs — exists)
├── /pricing                   (Section in /, sollte eigene URL bekommen für Backlinks)
├── /privacy /terms            (existieren)
│
├── /blog/                     (NEU — Index)
│   ├── claude-desktop-analytics-setup
│   ├── chatgpt-custom-connectors-analytics
│   ├── analytics-in-cursor
│   ├── all-mcp-tools-explained
│   ├── no-dashboard-experiment
│   ├── no-cookie-banner
│   ├── dsgvo-web-analytics-2024-dsk
│   ├── schrems-ii-eu-hosting
│   └── building-mcp-oauth-quirks
│
├── /vs/                       (NEU — Programmatic Bottom-of-Funnel)
│   ├── plausible
│   ├── fathom
│   ├── pirsch
│   ├── umami-cloud
│   ├── posthog
│   └── google-analytics
│
├── /mcp/                      (NEU — Programmatic Top-of-Funnel)
│   ├── get-overview
│   ├── top-pages
│   ├── top-referrers
│   ├── traffic-class-breakdown
│   ├── compare-periods
│   └── … (23 tools insgesamt)
│
├── /ai-crawler-index          (NEU — wöchentlich, Moat-Content; ab ~50 Pro-Kunden)
├── /ai-referrers-leaderboard  (NEU — wöchentlich, Moat-Content; ab ~50 Pro-Kunden)
│
└── /changelog                 (NEU — minimal, ein Eintrag pro Deploy)
```

**Erstmal-Skip** (Kosten/Nutzen schlecht): /case-studies (haben wir keine),
/customers (haben wir keine), /about/team (Single-Founder), /careers (lol),
/newsletter-archiv (Newsletter ist Distribution, nicht on-page strategy).

---

## 4. On-Page-SEO-Checkliste (technisch)

Für jeden neuen Content gilt:

- [ ] `<title>` ≤ 60 Zeichen, primäres Keyword vorne
- [ ] `<meta name="description">` 140–160 Zeichen, mit Click-Reason
- [ ] H1 == oder eng am `<title>`, exactly one
- [ ] H2-Outline, scannbar, Frage-orientiert wo möglich (LLM-friendly)
- [ ] FAQ-Section am Ende mit `<details>`/`schema.org/FAQPage` JSON-LD
- [ ] Schema.org `Article` JSON-LD für Blog, `Product` für `/`, `Comparison` für `/vs`
- [ ] Open-Graph + Twitter-Cards inkl. Custom OG-Bild (Template auf Basis
      vom existing `og-image.svg`)
- [ ] Canonical-URL gesetzt (für `/vs/`-Pages mit GET-Params wichtig)
- [ ] `sitemap.xml` automatisch erweitern (Rails: `app/views/sitemaps/`)
- [ ] `robots.txt`: AI-Crawler explizit *erlauben* (GPTBot, ClaudeBot,
      PerplexityBot) — wir wollen in deren Trainingsdaten
- [ ] Interne Verlinkung: jeder Blog-Post verlinkt 2× zu `/docs`, 1× zu
      `/`, 1× zu einem anderen Blog-Post (Topic-Cluster)
- [ ] Zielladezeit LCP < 2s (sind wir bei brutalist-mono ohne Bilder
      easy)
- [ ] Mobile-tauglich (brutalist-Layout ist's, aber Code-Blöcke prüfen
      auf horizontales Scroll)

**LLM/AI-Search-Optimierung** (eigene Kategorie, wird wichtiger):

- [ ] Frage als H2 → direkte Antwort im ersten Absatz darunter
- [ ] Konkrete Zahlen statt "viele/wenige" (LLMs zitieren bevorzugt
      Sätze mit Daten)
- [ ] Eindeutige Produktnennung "mcp-analytics" im ersten 100-Wort-Window
- [ ] Strukturierte Listen für "How-to"-Content (LLMs parsen das besser)
- [ ] Author-/Updated-Date schema (Trust-Signal für AI-Search)
- [ ] `llms.txt` im Root anlegen (siehe llmstxt.org Standard, 2025
      etabliert) — manuelles Site-Map für LLMs

---

## 5. Keyword-Strategie

### 5.1 Primäre Keyword-Cluster (Recherche-To-Do)

| Cluster | Beispiel-Terms | Priorität |
|---|---|---|
| **MCP-Tooling** | "mcp server analytics", "claude mcp setup", "claude desktop custom connector" | hoch (wachsend, niedrige KD) |
| **Plausible-Alternativen** | "plausible alternative", "self-hosted analytics", "cookieless analytics" | hoch (transaktional) |
| **DSGVO/Cookie** | "analytics ohne cookie banner", "dsgvo google analytics alternative", "schrems ii analytics" | mittel (DE-Volumen) |
| **AI-Crawler** | "gptbot pageviews", "claudebot referrer", "ai crawler traffic" | wachsend, kompetitiv mit CF |
| **AI-Referrer-Tracking** | "chatgpt traffic source", "perplexity referrer", "claude.ai outbound link" | wachsend, niedrige KD |

**Konkretes To-Do**: Mit den Ahrefs-MCP-Tools `keywords-explorer-overview`,
`keywords-explorer-matching-terms` und `keywords-explorer-related-terms`
pro Cluster die echten Volumes + KD ziehen, bevor wir Content-Slots
final priorisieren. Outputs landen in `MARKETING_KEYWORDS.md` (Followup).

### 5.2 Long-Tail-Strategie

Programmatic-Pages sollen Long-Tail abdecken:
`/mcp/top-referrers` rankt für "claude analytics top referrers tool",
"mcp top_referrers function", "how to get top referrers via mcp", etc.
**Nicht**: ein einziger Mega-Artikel "All MCP tools" der für alles
ranken soll — Google/LLMs bevorzugen einen sauberen 1-Tool-1-Page-Mapping.

### 5.3 Was wir nicht ranken werden (Realität)

- "web analytics" / "google analytics alternative" — Plausible/Matomo
  haben da DR60+ und 5 Jahre Backlinks. Ohne aggressive Linkbuilding-
  Strategie (= nicht on-page) verschwendet.
- Generische "best privacy analytics" Listicles — auf den Listen sind
  wir Outsider. Besser: *eigene* Vergleichs-Pages, wo wir den Frame
  setzen.

---

## 6. Cadence & Produktion (Single-Founder-Reality)

| Format | Frequenz | Effort | Wer |
|---|---|---|---|
| Cornerstone Blog-Post | 1/Monat | 1–2 Tage | Founder |
| Programmatic `/vs/*` | 6 Pages, eine Woche | Template + Daten | Founder, dann statisch |
| Programmatic `/mcp/*` | 23 Pages, zwei Wochen | Auto-generierbar aus `tool_schemas.rb` + Hand-Polish | Founder + Claude |
| AI-Crawler-Report | 1/Woche (ab ≥50 Pro) | Halb-automatisiert | Cron-Job + Hand-Kommentar |
| Build-in-Public-Post | 1/Woche (kurz) | 30 min | Founder, aus CLAUDE.md/Commits destilliert |
| Changelog-Eintrag | pro Deploy | 5 min | aus Kamal-Deploy-Hook autogen |

**Wichtig**: Cadence ist kein Selbstzweck. Lieber 1 saubere Cornerstone
pro Monat als 4 schlampige Posts/Woche. Brutalist-Stil verzeiht keinen
Floskel-Slop.

---

## 7. Produktions-Workflow

```
1. Idee → trello/Issue (keyword + persona + outcome)
2. Outline → 5-Punkt-Skelett (H1, H2s, hooks, internal links, CTA)
3. Draft in Markdown unter app/views/blog/_drafts/
4. Self-review:
   - Code/Chat-Snippet copy-pasteable und testbar?
   - 1 konkrete Zahl im ersten Absatz?
   - Persona klar identifizierbar?
   - Frame "Probleme zuerst, Tool zweitens"?
5. Render-Test lokal (bin/dev)
6. Publish → commit auf main → Kamal-Deploy → automatic sitemap-Eintrag
7. Track via mcp-analytics selber (Dogfooding):
   "claude, top pages für mcp-analytics.com letzte 7 Tage"
```

Drafts in Git committen (in `_drafts/` ordner, vom Renderer ignoriert) —
so kann der Founder per Claude Code an Drafts in jedem Container weiter-
arbeiten, ohne Notion/Google-Docs als Side-Channel.

---

## 8. CTAs & Conversion

Jeder Content-Pfad endet bei einer der folgenden Aktionen:

1. **`/` Email-Signup** (existing) — primary CTA für /blog/ und /vs/
2. **`/docs` Quickstart-Code** — primary CTA für /mcp/
3. **Direkt zur MCP-URL** für bestehende Claude-User
   (Connector-Add-Button-Pattern, sobald in Anthropic-Directory)

CTA-Hierarchie pro Page:

- **Hard CTA** (above fold, eine pro Page) — Email-Form bei Blog,
  "Try in Claude" bei /mcp/, "Compare Setup" bei /vs/.
- **Soft CTA** (im Fließtext, max. 2) — kontextuell, z.B. "Den
  vollständigen Setup-Guide gibt's in [/docs](/docs)".
- **Footer-CTA** (auto, jede Page) — minimal, eine Zeile, Email-Form
  oder Link zu /docs.

**Bewusst keine** Pop-ups, kein Exit-Intent, kein Newsletter-Modal,
keine "Cookies-akzeptieren"-Leiste (wir setzen keine!). Passt zum
Brutalist-Stil und Privacy-Positioning.

---

## 9. Messung & KPIs (dogfooded)

Wir tracken `mcp-analytics.com` mit mcp-analytics. Folgendes via Claude
abfragen (Beispiel-Prompts für den Founder als wöchentliche Routine):

```
"top pages für mcp-analytics.com letzte 7 Tage"
"compare periods last_7d vs previous_7d für /blog/*"
"top referrers letzte 30 tage"
"traffic class breakdown — wie viel davon ist Bot?"
"top user agents — sind GPTBot/ClaudeBot in der Liste?"
```

**Primäre KPIs**:

| KPI | Ziel Q3-2026 | Ziel Q4-2026 |
|---|---|---|
| Organic Sessions/Mo | 2 000 | 8 000 |
| Email-Signups aus Content | 50 | 200 |
| MCP-Connector-Activations aus Content-Pfad | 20 | 80 |
| `/vs/*`-Page-Bounce-Rate | <70% | <60% |
| Pro-Conversions aus Content (vs. Direct) | 5 | 25 |

**Sekundäre KPIs** (Trust-/Reach-Signals):

- AI-Citation-Rate: Wie oft wird `mcp-analytics.com` in Perplexity/
  ChatGPT-Antworten zitiert (manuell prüfen, monatlich, 10 relevante
  Queries)
- DR (Ahrefs Site-Explorer) — Ausgangsbasis messen, dann Wachstum
- Backlinks aus Hacker-News-/Reddit-Diskussionen über Crawler-Index

**Was wir nicht messen** (würde Privacy-Position untergraben):
individuelle User-Journeys, Heatmaps, Recordings, Personalisierung.
Strict-Mode-Aggregat ist genug.

---

## 10. Implementierungs-Roadmap (90 Tage)

**Status (Stand 2026-05-19)**: Wochen 1–6 + Top-of-Funnel + Moat-Shell
geshippt auf branch `claude/content-marketing-strategy-WvCyH`. Der
einzige offene Punkt ist die Live-Daten-Pipeline für den AI-Crawler-Index.

### Wochen 1–2: Foundation
- [x] `/blog` Index + Layout (markdown-backed via BlogPost model)
- [x] `/vs` Layout-Template (Tabelle + Verdict-Block + CTA via Comparison)
- [x] `/mcp/tools` Layout (autopopulated aus `tool_schemas.rb` via McpToolPage)
- [x] `sitemap.xml` dynamisch (SitemapsController, 46 Entries, mtime-aware lastmod)
- [x] `robots.txt` AI-Crawler explizit allowed (16 Bot-Stanzas mit Disallow für /oauth, /verify, /settings, /mcp$)
- [x] `llms.txt` (llmstxt.org-spec)
- [ ] OG-Image-Template parametrisiert (alle Pages nutzen aktuell die statische `og-image.png`)
- [x] Ahrefs-Keyword-Recherche → `MARKETING_KEYWORDS.md`

### Wochen 3–6: Bottom-of-Funnel
- [x] `/vs/plausible`, `/vs/fathom`, `/vs/pirsch`, `/vs/umami`, `/vs/posthog`, `/vs/simple-analytics`
- [x] `/vs/google-analytics` (EN) + `/de/vs/google-analytics`
- [x] `/de/vs/matomo`, `/de/vs/fathom`, `/de/vs/pirsch`
- [x] Cornerstones: `/blog/claude-mcp-setup` (EN, 2 560 Wörter), `/blog/llms-txt-explained` (EN, 2 003 Wörter), `/de/blog/mcp-server-anleitung` (DE, 2 483 Wörter)

### Wochen 7–10: Top-of-Funnel
- [x] 23 × `/mcp/tools/{slug}` Pages (autopopulated, plus 10 hand-polierte Example-Partials)
- [x] `/mcp/tools` Hub (gruppiert nach Tool-Kategorie)
- [x] `/blog/mcp-oauth-deep-dive` Authority-Cornerstone (3 200 Wörter, 11 Production-Quirks aus CLAUDE.md)

### Wochen 11–12: Moat-Content vorbereiten
- [x] `/ai-crawler-index` Page-Shell mit N=1-Demo + Disclaimer
- [ ] Crawler-Index-Pipeline: ClickHouse-Query → JSON → static page **(Live-Daten-Swap offen, Trigger: ≥50 Pro-Kunden)**
- [ ] Build-in-Public-Posts (3× kurz, aus CLAUDE.md destilliert)

**Critical-Path-Abhängigkeit**: Crawler-Index braucht 50+ Pro-Kunden für
glaubwürdige Datenbasis. Falls Pro-Conversion langsamer als geplant,
Säule C nach hinten. Säulen A+B reichen für die ersten 6 Monate
Acquisition.

---

## 11. Risiken & Mitigation

| Risiko | Wahrscheinlichkeit | Mitigation |
|---|---|---|
| Single-Founder-Burnout durch Cadence | hoch | 1 Cornerstone/Monat ist hard limit, nicht "stretch goal" |
| AI-Search dezimiert Click-Throughs auf eigene Site | hoch | Trotzdem produzieren — Citations = Awareness, auch ohne Click |
| Plausible/Pirsch kopieren MCP-Connector | mittel | First-Mover + 23-Tool-Tiefe schwer kopierbar in 3 Monaten; bis dahin Brand setzen |
| /vs/-Pages wirken aggressiv → Plausible-Twitter-Backlash | niedrig | Ehrlich vergleichen, Plausible-Open-Source explizit anerkennen |
| Crawler-Index braucht Daten, die wir noch nicht haben | hoch (kurzfristig) | Säule C nach hinten, mit N=1-Demos starten |
| AI-Crawler ignoriert `robots.txt`-Allow → keine LLM-Pickups | mittel | `llms.txt` zusätzlich, plus aktive Submission an Perplexity Pages |

---

## 12. Was explizit *nicht* in dieser Strategie ist

- **Off-Page**: Newsletter, Twitter/X-Threads, Reddit-Posts, Hacker-News-
  Launches, Gast-Posts, Podcast-Auftritte, Affiliate-Programm, Influencer-
  Outreach. Alles real wichtig, gehört in eine separate `DISTRIBUTION.md`.
- **Bezahlte Akquise**: Google-Ads, Reddit-Promoted, Newsletter-Sponsoring.
  Pre-Revenue nicht wirtschaftlich; nach ersten 100 Pro-Kunden re-evaluieren.
- **Video-Content**: YouTube-Tutorials, Loom-Demos. Hoher Produktions-
  Aufwand, schlecht parsbar für LLMs. Skip im MVP.
- **Community-Building**: Discord, Slack-Community, GitHub-Discussions.
  Bei Single-Founder unmoderierbar — erst ab Mitarbeiter #2.

---

## 13. Nächste Schritte (für den Founder)

1. **Diese Datei reviewen, was streichen / hinzufügen?** Insbesondere
   Persona-Section und Cadence-Realismus.
2. **Ahrefs-Keyword-Run kicken**: Drei MCP-Tool-Calls
   (`keywords-explorer-overview` für die 5 primären Cluster) →
   `MARKETING_KEYWORDS.md` schreiben. Kann Claude direkt in einer
   nächsten Session machen.
3. **`/blog` und `/vs` Layouts bauen** (Wochen 1–2 oben).
4. **Ersten Cornerstone schreiben** — Empfehlung: `/vs/plausible`, weil
   die Conversion-Wahrscheinlichkeit pro Visitor am höchsten ist und
   das Format danach 5× wiederverwendet wird.
