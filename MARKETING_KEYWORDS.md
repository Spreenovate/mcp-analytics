# MARKETING_KEYWORDS.md — Keyword-Research (Ahrefs, Mai 2026)

Begleit-Doc zu `CONTENT_MARKETING.md` §5. Quelldaten: Ahrefs Keywords
Explorer Overview, Country = US + DE, abgefragt 2026-05-19.

**Lese-Reihenfolge**: TL;DR → §3 "Quick Wins" → §4 Content-Slot-Mapping.

Werte: **Vol** = monatliches Suchvolumen im Markt, **KD** = Difficulty 0-100,
**TP** = Traffic Potential (was die #1-Page in Summe holt), **CPC** = USD-Cent.
"—" = unter Ahrefs-Mess-Threshold (typischerweise <10).

---

## TL;DR

1. **Bester EN-Pfad ist nicht /vs/plausible, sondern MCP-Tooling.**
   "claude mcp" 5 000/Mo bei **KD 12**, "anthropic mcp" 2 300, "best mcp
   servers" 1 300 KD 38 — das ist ein offenes Spielfeld mit hoher Intent.
2. **`/vs/google-analytics` schlägt `/vs/plausible`.** GA-Alt hat 1 200/Mo
   bei KD 25, "plausible alternative" nur 50/Mo. Vergleichs-Page-Slot
   neu priorisieren.
3. **"llms.txt" (3 700/Mo, KD 39)** ist überraschend zugänglich und
   passt thematisch ideal — Cornerstone-Slot reservieren.
4. **AI-Crawler-Cluster ist gold und billig.** "claudebot" 2 100/Mo
   KD 13, "gptbot" 350/Mo KD 8, "bytespider" 150/Mo KD 2 — alles
   programmatic-tauglich. Das ist genau der Moat-Content aus
   `CONTENT_MARKETING.md` Säule C.
5. **DE-Markt: "mcp server" hat 14 000/Mo bei KD 22.** Anomalie —
   im US-Markt KD 60, in DE KD 22. Wahrscheinlich Mess-Artefakt
   (weniger competitive Pages auf Deutsch), aber selbst halbiert ein
   gigantischer Slot. **Erster Quick-Win: ein deutschsprachiger
   MCP-Server-Setup-Guide.**
6. **Tot-Cluster**: "ai traffic source", "chatgpt referrer",
   "perplexity traffic", "ai agent analytics", "bot traffic analytics"
   haben praktisch null Volumen. Wir würden den Slot *kreieren*, nicht
   Demand bedienen. Trotzdem produzieren (für AI-Search-Zitate, nicht
   Google-Traffic), aber Aufwand minimieren.

---

## 1. Cluster A — MCP-Tooling (Top-Funnel)

### 1.1 US (en)

| Keyword | Vol | KD | TP | Intent | Notiz |
|---|---:|---:|---:|---|---|
| `mcp server` | 62 000 | 60 | 78 000 | info | Hub-Term. Direkt-Ranking unrealistisch, Parent-Topic-Strategie via Sub-Pages |
| `model context protocol` | 23 000 | 86 | 78 000 | info | Brand-/Standard-Term, KD zu hart, Backlinks-Game |
| `claude mcp` | **5 000** | **12** | 90 | info+brand | **★ Gold-Slot**. KD niedrig, Volumen hoch. Ein Cornerstone "Claude MCP Setup". |
| `anthropic mcp` | 2 300 | — | — | info | Wahrscheinlich KD ähnlich claude mcp. Hand-Polish im selben Hub. |
| `best mcp servers` | 1 300 | 38 | — | listing | Eigene Listicle oder /mcp Hub-Page muss hier ranken |
| `mcp client` | 1 700 | 50 | 600 | info | Eher Dev-Konkurrenz (Cline, Continue) — passend für Tutorial-Verlinkung |
| `mcp server list` | 1 000 | 68 | — | listing | DR-Game, Aufwand vs. Ertrag schwach |
| `claude desktop mcp` | **900** | **34** | 150 | info+brand | **★ Cornerstone-Slot** — `/blog/claude-desktop-analytics-setup` |
| `mcp tutorial` | 600 | 53 | — | info+brand | Schwer (Anthropic eigenes Tut rankt), Long-Tail-Variante besser |
| `build mcp server` | **500** | **15** | — | info | **★** Dev-Cluster, Tutorial-Slot |
| `mcp oauth` | 450 | — | — | info | **★** Hier haben wir einzigartige Authority (OAUTH_BRIEFING.md). KD vermutlich niedrig |
| `mcp directory` | 450 | — | — | info+brand | Eigene Page "Welche MCP-Directories gibt es" |
| `mcp examples` | 350 | — | — | info | Listicle-Style |
| `remote mcp server` | 200 | — | — | info | Eng zu uns (wir SIND ein remote MCP server) |
| `how to set up mcp server` | 90 | 10 | — | how-to | **★** Long-Tail, KD 10, free win |
| `mcp tools` | 900 | 36 | — | info | Ambig (parent_topic: "structured schema") — Vorsicht beim Targeting |
| `chatgpt custom connector` | 10 | — | — | brand | Volumen klein, aber wachsend (ChatGPT Connectors sind 2025-Feature) |
| `claude custom connector` | 20 | — | — | brand | dito |

**Strategie EN-MCP**:
- 1 Cornerstone-Hub `/blog/claude-mcp-setup` (zielt auf "claude mcp", "claude desktop mcp", "how to set up mcp server")
- 1 Authority-Piece `/blog/mcp-oauth-quirks` (zielt auf "mcp oauth", differenziert über reale Bugs aus CLAUDE.md)
- 1 Listicle `/blog/best-mcp-servers-2026` (Liste inkl. uns; ehrlich, mit Konkurrenz)
- Programmatic-Hub `/mcp/` (Tool-Pages, fängt Long-Tail)

### 1.2 DE (de)

| Keyword | Vol DE | KD DE | TP | Notiz |
|---|---:|---:|---:|---|
| `mcp server` | **14 000** | **22** | 5 800 | **★ Anomalie**. KD niedrig in DE, hohes Volumen. Erste DE-Page bauen. |
| `model context protocol` | 4 400 | 70 | 5 300 | Hard, aber Sub-Topic-Game lohnt |
| `claude desktop` | 3 500 | 38 | 1 300 | Setup-Guide passt — Vehikel, nicht Ziel |
| `claude api` | 1 700 | 38 | 1 100 | Eng zu uns nur, wenn wir API-Vergleich machen |
| `cursor ide` | 1 700 | 25 | 12 000 | Tangential — Setup-Guide "Analytics in Cursor" |
| `claude pro` | 1 600 | 0 | 400 | KD 0, aber Intent ist *Abo-Vergleich*, nicht unser Game |
| `chatgpt connectors` | 150 | — | — | DE schreibt "Konnektoren" — Variante prüfen |
| `ki crawler` | 100 | — | — | DE-Variante zu "ai crawler" |
| `claude analytics` | 0 | — | — | Demand erst zu kreieren |
| `ai agent analytics` | 0 (DE) | — | — | Tot |

**Strategie DE-MCP**:
- Cornerstone `/de/blog/mcp-server-anleitung` (zielt auf "mcp server" DE) — höchster ROI in der ganzen Recherche
- Zweit-Page `/de/blog/claude-desktop-einrichten-mit-analytics`

---

## 2. Cluster B — Privacy/Plausible-Alternativen (Bottom-Funnel)

### 2.1 US (en)

| Keyword | Vol | KD | TP | CPC | Notiz |
|---|---:|---:|---:|---:|---|
| `google analytics alternative` | **1 200** | **25** | 1 400 | 700 | **★★ Bester Vergleichs-Slot**. KD 25 ist machbar, CPC 7$ = commercial intent. |
| `simple analytics` | 4 600 | 11 | 3 300 | 350 | Branded — nicht ranken, aber `/vs/simple-analytics` für Long-Tail |
| `cookieless analytics` | **100** | **6** | 150 | 700 | **★** KD 6 + CPC 700 = niedrige Hürde, hohe Conversion. Cornerstone dazu. |
| `self hosted analytics` | 150 | 56 | 150 | 350 | DR-Game, schwer |
| `privacy focused analytics` | 100 | 80 | 50 | 250 | KD 80 — vergessen |
| `plausible alternative` | 50 | 1 | 20 | — | KD 1 aber Volumen winzig; Page bauen weil free win |
| `posthog alternative` | 100 | — | — | — | Geringer Schätz-Confidence; trotzdem Page |
| `fathom analytics alternative` | 50 | — | — | — | dito |
| `pirsch analytics` | 50 | — | — | — | Branded Konkurrenz |
| `umami analytics` | 50 | 0 | 1 000 | 500 | KD 0 — wert anzugehen via /vs |

### 2.2 DE (de)

| Keyword | Vol DE | KD DE | TP | CPC | Notiz |
|---|---:|---:|---:|---:|---|
| `google analytics alternative` | **250** | **0** | 200 | 200 | **★ KD 0** — machbar, sofort Page bauen |
| `fathom analytics` | 250 | 0 | 150 | 250 | Branded — `/de/vs/fathom` |
| `pirsch analytics` | 90 | 0 | 30 | — | dito `/de/vs/pirsch` |
| `matomo alternative` | 60 | 0 | 20 | 250 | `/de/vs/matomo` |
| `analytics ohne cookies` | 40 | — | — | 250 | Cornerstone-DE Slot |
| `plausible alternative` | 30 | — | — | 60 | Sehr klein |
| `cookieless analytics` | 30 | — | — | 300 | Sehr klein |
| `etracker alternative` | 0 | — | — | — | Tot |
| `dsgvo konform analytics` | 0 | — | — | — | Demand-Phrase nicht etabliert; "DSGVO + Google Analytics" wahrscheinlich aussagekräftiger |

**Strategie B**:
- **EN-Reihenfolge umdrehen vom ursprünglichen Plan**:
  1. `/vs/google-analytics` (1 200 Vol, KD 25) — *erst*
  2. `/blog/cookieless-analytics-explained` (100 Vol, KD 6, CPC 7$)
  3. `/vs/simple-analytics`, `/vs/umami`, `/vs/plausible`, `/vs/fathom`, `/vs/pirsch`, `/vs/posthog` als Programmatic-Batch
- **DE-Slots** alle mit KD 0 — alle 4 Pages produzieren, niedriger Aufwand
  (kann von EN-Page übersetzt werden), wahrscheinlich >50% Top-3 binnen
  3 Monaten.

---

## 3. Cluster C — AI-Crawler (Moat-Content)

### 3.1 US (en)

| Keyword | Vol | KD | TP | Notiz |
|---|---:|---:|---:|---|
| `claudebot` | **2 100** | **13** | 1 400 | **★★ Goldkern**. KD 13 + Vol 2k. Eigene Page mit Live-Daten. |
| `llms.txt` | **3 700** | **39** | 3 600 | **★★** Cornerstone — passt thematisch perfekt zur unserer Site (wir setzen llms.txt) |
| `gptbot` | 350 | 8 | 250 | **★** KD 8, eigene Detail-Page |
| `gptbot user agent` | 150 | — | — | Long-Tail-Variante |
| `bytespider` | 150 | 2 | 150 | **★** KD 2 = quasi gratis ranken |
| `ai crawler` | 300 | 43 | 30 | Mid-KD, TP klein |
| `ai bot detection` | 100 | 62 | 889 000 | TP-Zahl irreführend (parent topic "ai detector" = anderer Markt) |
| `perplexitybot` | 80 | — | — | Free win |
| `block ai crawlers` | 50 | — | — | Use-case-spezifisch, gerne hand-poliert |
| `robots.txt ai` | 10 | — | — | Niedrig, aber semantisch perfekt zu llms.txt |
| `chatgpt traffic` | 200 | 38 | 70 | Mid-KD |
| `ai search optimization` | 4 800 | 58 | 1 100 | Hard, viel SEO-Konkurrenz |
| `generative engine optimization` | 12 000 | 66 | 5 200 | Sehr hard — Backlinks-Game |
| `chatgpt referrer` | 0 | — | — | Tot |
| `ai traffic source` | 0 | — | — | Tot |
| `perplexity traffic` | 10 | — | — | Praktisch tot |

**Strategie C**:
- **Cornerstone `/blog/llms-txt-explained`** (3 700 Vol KD 39). Erkläre llms.txt, zeige unser eigenes File, verbinde mit MCP-Wedge.
- **`/ai-crawler-index` Hub-Page** ranked als landing für "claudebot", "gptbot", "bytespider". Sub-Pages `/ai-crawler-index/claudebot` etc.
- Programmatic-Batch: 6–8 Bot-Detail-Pages (jeweils 400 Wörter: Beschreibung, User-Agent-String, IP-Ranges falls publik, robots.txt-Snippet, Live-Hits aus unserem Aggregat).
- **AI-Search-Optimization-Cluster aufgeben für Direkt-Ranking** (KD 58–66) — aber Inhalte mit dem Vokabular schreiben, sodass wir in Perplexity/ChatGPT-Antworten zitiert werden.

### 3.2 DE (de)

| Keyword | Vol DE | KD | Notiz |
|---|---:|---:|---|
| `ki crawler` | 100 | — | Übersetzung "ai crawler". Vermutlich KD niedrig. |

DE-Cluster für Crawler dünn. Pages translatieren auf Anfrage, kein Prio.

---

## 4. Content-Slot-Mapping (aktualisiert, ersetzt §5 in CONTENT_MARKETING.md)

### 4.1 Erste 8 Cornerstones (priorisiert nach ROI = Vol × Conversion-Potential ÷ KD)

| # | Slot | URL | Ziel-Keyword (Vol/KD) | Markt | Aufwand | ROI |
|---:|---|---|---|---|---|---|
| 1 | DE-MCP-Setup | `/de/blog/mcp-server-anleitung` | "mcp server" (14k/22) | DE | mittel | **A+** |
| 2 | Claude-MCP-Setup | `/blog/claude-mcp-setup` | "claude mcp" (5k/12) | EN | mittel | **A+** |
| 3 | llms.txt Erklärt | `/blog/llms-txt-explained` | "llms.txt" (3.7k/39) | EN | mittel | **A** |
| 4 | ClaudeBot-Detailseite | `/ai-crawler-index/claudebot` | "claudebot" (2.1k/13) | EN | klein | **A** |
| 5 | /vs/google-analytics | `/vs/google-analytics` | "google analytics alternative" (1.2k/25) | EN | mittel | **A** |
| 6 | MCP-OAuth-Authority | `/blog/mcp-oauth-deep-dive` | "mcp oauth" (450) | EN | klein (CLAUDE.md-Material) | **B+** |
| 7 | DE GA-Alt | `/de/vs/google-analytics` | "google analytics alternative" DE (250/0) | DE | klein (übersetzt aus #5) | **B+** |
| 8 | Cookieless erklärt | `/blog/cookieless-analytics-explained` | "cookieless analytics" (100/6, CPC 7$) | EN | klein | **B+** |

### 4.2 Programmatic-Batches (templated)

| Batch | Anzahl | Aufwand | Ziel-Pattern |
|---|---:|---|---|
| `/mcp/{tool}` | 23 | aus `tool_schemas.rb` autogen + Hand-Polish | Long-Tail (z.B. "claude top referrers tool") |
| `/vs/{competitor}` | 6 EN + 4 DE | 1 Template, Daten per Competitor | "X alternative" Long-Tail |
| `/ai-crawler-index/{bot}` | 6–8 | aus Live-Daten + Template | "claudebot", "gptbot", "bytespider", etc. |

### 4.3 Build-in-Public / Founder-Story-Slots

Niedrige Suchvolumen-Zielsetzung — diese Pieces ranken nicht primär,
sondern liefern Trust + AI-Search-Citations. Mit Kontext bereits in
`CLAUDE.md` dokumentiert (z.B. MCP-OAuth-Quirks, sed-u-Story,
single-server-Pricing-Spin).

### 4.4 Was wir aus dem ursprünglichen Plan herauswerfen

- **`/vs/plausible` als erste Vergleichs-Page**: Volumen zu klein (50 US,
  30 DE). Bleibt im Programmatic-Batch, nicht Cornerstone.
- **`/blog/dsgvo-web-analytics-2024-dsk`**: Keyword "dsgvo konform analytics"
  hat **0** Volumen. Demand-Phrasen anders ("google analytics dsgvo" o.ä.)
  — neue Recherche-Runde nötig, bevor wir das Cornerstone-Slot vergeben.
- **`/blog/chatgpt-custom-connectors-analytics`**: "chatgpt custom connector"
  10 Vol, "chatgpt connectors" 150 — zu klein für Cornerstone. Als kürzerer
  Tutorial-Beitrag mitnehmen, nicht als Säulen-Piece.
- **`/ai-referrers-leaderboard`** als Keyword-Targeting-Slot: "chatgpt
  referrer" = 0 Vol. Page trotzdem bauen für AI-Citations und PR, nicht
  für Google-Traffic. Erwartung managen.

---

## 5. Methodik & Vorbehalte

- **Ahrefs-Stichtag**: 2026-05-19, "volume" = trailing 12 Monate.
- **KD ist Ahrefs-Schätzwert**, nicht Boden. Bei `null` (8 Keywords im
  Set) liegt KD wahrscheinlich niedrig oder Daten unzureichend.
- **TP (Traffic Potential)** ist die Summe aller Keywords, die die #1-Page
  rankt — nützlicher als reines Vol, aber überzeichnet wenn die #1 eine
  Wikipedia-Page ist.
- **"google analytics alternative" KD 0 in DE** ist ungewöhnlich; halte
  KD 10–20 für realistischer und plane entsprechend (mehrere
  Linkquellen + interne Verlinkung).
- **Branded Keywords** (umami, fathom, plausible, claude-*) sind oft
  KD 0 aber Intent ist primär *zur Marke*, nicht "Alternative-Suche".
  /vs-Pages fangen die schmale Untermenge, die nach Vergleich sucht.

---

## 6. Next-Run-To-Dos

- [ ] **DE-DSGVO/Cookie-Cluster nachrecherchieren** — Phrasen wie
      "google analytics dsgvo verstoss", "matomo dsgvo", "analytics
      tools dsgvo konform", "cookie banner pflicht". Aktueller Run
      hat hier dünnen Datensatz.
- [ ] **`keywords-explorer-matching-terms` für "mcp"** mit
      Filter `volume >= 50 AND difficulty <= 30` — fängt Long-Tail
      den wir noch nicht kennen.
- [ ] **`keywords-explorer-related-terms` für "claudebot"** —
      welche "also-rank-for" Keywords gibt's? Wichtig für
      AI-Crawler-Hub-Strukturierung.
- [ ] **`serp-overview` für die 8 Cornerstones** — wer rankt aktuell,
      welche DR haben sie, gibt es Wikipedia/Reddit-Konkurrenz? Wenn
      AI-Overview-Box bereits dominiert, KD-Wert unterzeichnet die
      Realität.
- [ ] **Volume-History** für "claude mcp", "mcp server", "llms.txt" —
      Wachstumstrends bestätigen vor 6-Monats-Wette.

Diese Folge-Recherche braucht ~3000 Ahrefs-Units (von 49 000 verbleibend).
