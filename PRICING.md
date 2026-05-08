# PRICING.md — final, Mai 2026

Working-Doc parallel zu `BRIEFING.md`. Gelandet nach Subagent-Recherche
(Plausible/Pirsch/Fathom-Floor + CF-AICC + Sentry-MCP) und kritischer
Bewertung mehrerer Vorschlagsvarianten. Vorgängerstand siehe Git-History
dieses Files (Commit 718c5c2).

## TL;DR

```
Free       100k Hits/Mo, unlimited Sites, JS-Tracker only,
           alle 23 MCP-Tools, 1 J Retention, no card
Pro €19/Mo 10M Hits, unlimited Sites, alle Features:
           Bot/AI-Taxonomie, Server-Side SDK, Deploy-Regression
           GH-Action, 3 J Retention, Priority-Support
           €1 pro zusätzliche 1M Hits (hard-cap default,
           opt-in Auto-Overage)
Enterprise ab €299/Mo — dedicated Server, query_sql, SLA,
           custom Retention, white-label Tracking-Domain, DPA
           Contact Sales (enterprise@mcp-analytics.com)
```

**Bewusst nicht im Pricing**: kein Annual (Y2-Problem, manuelle
Behandlung wenn Kunden fragen), kein Studio-Tier (Pro-Active-Features
sind Y2-Theater bei Single-Founder), keine Team-Seats (UI-loses
MCP-Produkt — "Seats" lösen kein reales Bedürfnis), keine zweite
Pillar (MCP-Server-Analytics) im UI. Single-Founder-Pre-Launch — was
wir nicht in Studio-Quality bauen können bevor wir 50 zahlende Kunden
haben, ist kein Pricing-Differenzierer.

---

## 1. Markt-Landkarte (recherchiert Mai 2026)

### Privacy-first Web-Analytics — direkter Wettbewerb

| Player          | Free          | Erster Paid           | Bemerkung                                          |
|-----------------|---------------|------------------------|----------------------------------------------------|
| **Plausible**   | keiner        | $9/Mo · 10k pv         | Open-Core-Halo, EU. Kein Free → unser Acq-Vorteil. |
| **Pirsch**      | 30d Trial     | **$6/Mo · 10k pv**     | DE-hosted, billigster credible EU.                 |
| **Fathom**      | 30d Trial     | $15/Mo · 100k pv       | Premium-UX, "unlimited sites".                     |
| **Umami Cloud** | **1M events** | ~$20/Mo Pro            | Dickste Free-Decke, OSS.                           |
| **PostHog**     | 1M events     | volume-based           | Suite, nicht Plausible-Form.                       |
| **Matomo Cloud**| 21d Trial     | **€29/Mo · 50k Hits**  | Premium-Anker (Heatmaps/A-B/Recordings).           |
| **Cloudflare WA**| Free         | —                      | 10% gesampelt, Top-15-Cap. Kein echtes Produkt.    |
| **GoatCounter** | unlimited     | $5/Mo                  | Hobby-Floor, single-Maintainer.                    |

**Mental Anchor für Indie-AI-Käufer**: Claude Pro $20, Cursor Pro $20,
Sentry Team $26 — das ist der relevante Korridor, nicht $9 Plausible.

**MCP-native kommerziell live**: keiner. GitHub-only-Wrapper
(plausible-mcp etc.) sind Hobby-Projekte ohne Ingest. Slot offen.

### Bot-/AI-Agent-Traffic — defensives Feature

| Player                     | Einstieg       | Indie-tauglich? |
|----------------------------|----------------|-----------------|
| **Cloudflare AI Crawl Ctrl** | Free (CF)    | Sieht ALLES bei CF-Kunden — kompletter Origin-View, nicht "nur CF-Traffic" wie v1 dieses Docs fälschlich behauptet hat. |
| **DataDome / HUMAN / Imperva / Akamai** | $1k+/Mo | Enterprise-only |
| **Vercel BotID**           | bundled        | Nur Vercel-Hostings |
| **Arcjet**                 | $25/Mo         | SDK-style, dev-first, kein per-Bot-Pageview-Report |
| **Promptwatch**            | $99/Mo · 2 Sites | Dichtester Indie-Konkurrent |
| **Plausible/Fathom/Pirsch**| —              | Filtern Bots silently. Pirsch hat AI-*Referrer*-Channel (Mensch aus ChatGPT), nicht Crawler-View |

**Honest Wedge-Korrektur**: Bot-Sicht ist *kein* struktureller Wedge gegen
CF-AICC für CF-Kunden — CF sieht bei eigenen Kunden alles. Unser Bot-Wedge
greift nur bei (a) Non-CF-Kunden im Long-Tail (~50–80% kleinerer Sites)
und (b) Konsolidierung "ein Tool für alle Fragen statt drei Tabs". Letzterer
ist schwach, kopierbar.

---

## 2. Eigene Kostenbasis

Hetzner CX32 in Falkenstein, 4 vCPU, 8 GB, 80 GB SSD, 20 TB Egress = **€7.50/Mo**.
Plus Backup, Postmark/SES, Domain, GHCR-frei → ~**€17/Mo Infra-COGS** für
single-host. Bis ~50–100 zahlende Kunden tragbar; danach CX42 (€14/Mo, 160 GB).

Marginalkosten pro 10M-Hits-Kunde im Steady-State:

| Position             | Verbrauch                  |
|----------------------|----------------------------|
| Storage (komprimiert) | ~800 MB/Mo (~30 GB Lifetime bei 3 J) |
| Egress               | ~10 GB/Mo                  |
| Compute              | vernachlässigbar           |
| **Marginal-Cost**    | **~€0.10–0.30/Mo**         |

Bei €1/1M Overage = ~95% Marge. Risikolos pricebar.

---

## 3. Wedge & ehrliche Positionierung

In absteigender Stärke:

1. **MCP-native als Primärinterface.** Der einzig wirklich strukturelle
   Wedge. Niemand sonst kommerziell, weil's bedeutet eigene Dashboard-
   Brand zu kannibalisieren.
2. **Origin-Tracking für Non-CF-Sites** via Server-Side-Middleware
   (Roadmap-Phase 4B/4C). CDN-only-Lösungen erreichen den Long-Tail nicht.
3. **Konsolidierung** — eine MCP-Verbindung statt drei Tools. Schwacher
   Wedge, schnell kopierbar.
4. **Deploy-Regression-Loop in Claude** (`record_deploy` + `regression_check`
   MCP-Tools + GH-Action). Kleine Quirk-Differenzierung.
5. ~~Bot-Sicht~~ — strukturell verloren gegen CF-AICC für CF-Kunden.
   Bleibt als Convenience-Feature in Pro inkludiert, nicht als Daten-
   Differenzierung verkaufen.

**Anti-Wedges (nicht draufpreisen):**
- EU-Hosting / GDPR — 2026 Tablestakes, Pirsch/Matomo haben's auch
- Open-Source-Halo — Plausible besetzt das, wir sind proprietär
- Lifetime-Deals — tot in 2026, niemand fährt sie mehr

---

## 4. Pricing — final

### Free — €0 forever

- 100k Hits/Mo (kombiniert über alle Sites)
- Unlimited Sites
- JS-Tracker (`script.js`)
- Alle 18 MCP-Analytics-Tools
- 3 Privacy-Modi (strict/default/all)
- 1 Jahr Retention
- Community-Support (GitHub Issues)
- Keine Kreditkarte

**Behält das öffentliche README-Versprechen.** Conversion-Druck kommt nicht
über Volumen sondern über **Features**: kein Bot-Taxonomie-View, kein
Server-Side-SDK, kein Deploy-Hook, kein record_event. Power-User merken
Tag 1 was fehlt.

### Pro — €19/Mo

Anchored am Claude/Cursor-Korridor ($20). Über Plausible $9 (Step-Up,
nicht Substitut), unter Fathom $15/100k bei 100× Volumen.

- **10M Hits/Mo**
- Unlimited Sites
- **Bot-/AI-Agent-Traffic-Taxonomie** (Phase 1 done, Phase 2 Cloudflare-
  kompatible Klassen Roadmap)
- **Server-Side-SDK**: Ruby-Gem `mcp-analytics-rack`, npm-Package, Pixel-Endpoint
- **Deploy-Regression-Bundle**: GH-Action + MCP-Tools `record_deploy`/
  `regression_check`
- **`record_event` Server-Side-Event-Tool**
- 3 Jahre Retention
- Priority-E-Mail-Support, 24h-Antwort
- **€1 pro zusätzliche 1M Hits** (hard-cap default mit Email-Warnung
  bei 80%/100%, Auto-Overage opt-in im Settings)

### Enterprise — ab €299/Mo, custom

Bestehender `enterprise@mcp-analytics.com`-Funnel; heutige Trigger
(Mail bei >150% Free-Tier, Operator-Alert) bleiben Lead-Source.

- Dedizierter Hetzner-Host (CX42+, single-tenant ClickHouse)
- **`query_sql` Power-Tool** — direktes SQL gegen die eigene ClickHouse
- **Web-Bot-Auth-Signaturverifikation** (Phase 3) — verifizierte vs.
  spoofed Agents getrennt
- DPA, SLA 99.9%, Audit-Log, SAML/SSO
- Custom-Retention (bis 7 J), Custom-Tracking-Domain
- White-Label-Tracking-Skript
- Onboarding-Call + dedicated Slack-Connect

---

## 5. Warum das hält — Konkurrenzmatrix

| Konkurrent       | Tier            | Hits  | Sites | Bot   | SDK   | MCP   | Deploy | Preis |
|------------------|-----------------|-------|-------|-------|-------|-------|--------|-------|
| **Plausible**    | $9 Starter      | 10k   | 1     | nein  | nein  | nein  | nein   | $9    |
| **Pirsch**       | $6 Standard     | 10k   | 50    | Ref   | nein  | nein  | nein   | $6    |
| **Fathom**       | $15 Entry       | 100k  | 50    | nein  | nein  | nein  | nein   | $15   |
| **Umami Cloud**  | Free            | 1M    | viele | nein  | nein  | nein  | nein   | 0     |
| **CF AICC**      | Free (CF only)  | unlim | nur CF| ja    | nein  | nein  | nein   | 0     |
| **Promptwatch**  | $99 Essential   | ?     | 2     | ja    | ?     | nein  | nein   | $99   |
| **Sentry Team**  | $26             | n/a   | n/a   | n/a   | n/a   | wrap  | nein   | $26   |
| **wir Free**     | €0              | 100k  | ∞     | nein  | nein  | **ja**| nein   | **0** |
| **wir Pro**      | €19             | 10M   | ∞     | ja    | **ja**| **ja**| **ja** | **€19**|

**Strukturelle Verteidigungslinien:**

1. **Plausible/Fathom/Pirsch geben null free** — unser 100k-Free-Tier
   lockt Switcher die "ich will probieren ohne Card" suchen. Sie können
   das nicht matchen ohne ihr Pricing-Modell zu sprengen (sie haben
   Frontend-COGS, wir nicht).
2. **Sentry MCP Monitoring** ist APM-shaped, wir Analytics-shaped. Sie
   wollen Errors-First-Buyer, wir Build-Audience-Buyer. Selbe Daten,
   andere Frage, anderer Buyer.
3. **CF-AICC ist kein Web-Analytics-Tool**, es ist ein Crawler-Dashboard.
   Wer Plausible+CF+AICC nutzt hat drei Tools für drei Fragen — wir
   konsolidieren in einer MCP-Verbindung.

**Kipp-Risiken (re-evaluate triggers vor Pricing-Go-Live):**

- Anthropic shipped first-party Connector-Analytics (heute punted FAQ explizit auf Drittanbieter)
- Plausible kauft MCP-Wrapper als offizielles Feature ($19 Pro)
- Cloudflare erweitert AICC zu allgemeiner Web-Analytics
- Sentry Ruby-MCP-SDK aus Beta gezogen

Wenn eines eintritt → Wedge neu begründen.

---

## 6. Roadmap-Mapping

Welches BRIEFING-Roadmap-Feature welchem Tier angehört:

| Feature                                          | Free | Pro | Enterprise |
|--------------------------------------------------|------|-----|------------|
| JS-Tracker + alle 18 MCP-Analytics-Tools         | ✓    | ✓   | ✓          |
| 3 Privacy-Modi                                   | ✓    | ✓   | ✓          |
| Bot-Phase 1 (binary `traffic_class` + UA)        | ✓    | ✓   | ✓          |
| Bot-Phase 2 (Cloudflare-kompatible Taxonomie)    | —    | ✓   | ✓          |
| Bot-Phase 4A Pixel-Endpoint                      | —    | ✓   | ✓          |
| Bot-Phase 4B Ruby-Gem                            | —    | ✓   | ✓          |
| Bot-Phase 4C Node/Next-Middleware                | —    | ✓   | ✓          |
| Bot-Phase 4D CF-Worker / Vercel-Edge             | —    | ✓   | ✓          |
| `record_event` Server-Side-Event-Tool            | —    | ✓   | ✓          |
| Deploy-Regression GH-Action + MCP-Tools          | —    | ✓   | ✓          |
| Bot-Phase 3 Web Bot Auth Signaturen              | —    | —   | ✓          |
| `query_sql` Power-Tool                           | —    | —   | ✓          |
| MaxMind Geo-Lookup                               | —    | —   | ✓          |
| Custom-Tracking-Domain                           | —    | —   | ✓          |
| White-Label-Skript                               | —    | —   | ✓          |
| DPA / SAML / Audit-Log                           | —    | —   | ✓          |
| 1 J / 3 J / custom Retention                     | 1 J  | 3 J | custom     |

**Roadmap-Lücke (im BRIEFING noch nicht erwähnt)**: Deploy-Regression-
Tools `record_deploy(commit_sha, env)` + `regression_check(period,
baseline)` plus offizielle GH-Action `mcp-analytics/record-deploy@v1`.
~3-4h Aufwand. Sollte in BRIEFING.md als Phase-2-Item nachgezogen werden.

---

## 7. Realistische Adoption Y1

Vom Subagent-Critic geschätzt, kontextualisiert an Plausible (~3 Jahre
für $50k MRR mit HN-Karma-Vorsprung):

| Metrik                  | Erwartung                          |
|-------------------------|------------------------------------|
| Free-Signups Y1         | 800 – 1.500                        |
| Paid-Kunden Y1          | 50 – 100                           |
| MRR Ende Y1             | **€1.000 – 2.000** + €100–300 Overage |
| Churn-Rate Y1 / Y2      | 5–7 % / 3–4 %                      |

**Annahme**: 3–5h/Woche Content/Distribution (Twitter/X, Indie-Hackers,
ProductHunt, Show-HN-Reload nach Initial-Launch). Bei reinem
"build it and they will come" alle Zahlen halbieren.

**Hauptchurner**: Indie-Hacker dessen Side-Project tot ist (~60% der
ersten 100 Käufer). Strukturell, nicht prizable. Plausible hat das
gleiche Problem.

**Welle-Erwartung**: Welle 1 (Monat 0–6) = AI-native Indie-Hacker, "ich
frag Claude meine Stats"-Demo charmant. Welle 2 (Monat 9–12) = eigentliche
Privacy-Analytics-Käufer, langsamer, SEO-getrieben.

---

## 8. Risiken

1. **Stripe-Integration-Aufwand** — Pro-Tier braucht Stripe-Checkout +
   `subscriptions`-Modell + Tier-Enforcement im `Mcp::AuthContext`.
   ~1–2 Tage. Vor Go-Live nötig.
2. **Lemon-Squeezy als Alternative** für EU-VAT-Handling
   (Merchant-of-Record). Bei <€100k MRR ist deren 5% + 50ct kleiner als
   eigene VAT-Compliance.
3. **Hard-cap-Implementierung muss vor Pro-Launch live sein**, sonst
   können Free-User unbegrenzt einsenden (Cost-Risk). Heute ist's Soft-
   Warning ("Daten ab Datum X unvollständig"), muss zu echter 429er
   werden für Free-Accounts über Cap.
4. **Free-Tier-Abuse als Backend-Speicher**. Mitigation: tägliche
   MCP-Tool-Calls auf z.B. 200 für Free deckeln (Speicher billig,
   MCP-Antwort-Tokens teuer für uns).
5. **Annual-Anfragen werden manuell bedient** bis Y2. Wenn das Volumen
   >5 Anfragen/Monat wird, automatisieren.

---

## 9. Implementierungs-Followups

In Reihenfolge:

1. **`subscriptions`-Modell + tier enum auf User** (`hobby`/`pro`/
   `enterprise`). Default `hobby`. ~4h.
2. **Tier-Enforcement im `Mcp::AuthContext`** — Bot-Tools, SDK-Endpunkte,
   Deploy-MCP-Tools schalten anhand `User#tier`. ~4h.
3. **Hits-Cap-Hard-Enforcement** für Free-Tier — heute Soft-Warning, muss
   429 für Free-Accounts über Cap werden. Solid-Cache-basiert, ~2h.
4. **Stripe-Checkout + Webhook** (`SubscriptionsController#sync`).
   Lemon-Squeezy als Alternative evaluieren. ~1–2 Tage.
5. **Overage-Cron** — Solid-Queue-Job am Monats-Ultimo, summiert Hits
   über Cap, fügt `Stripe::InvoiceItem` hinzu. ~2h.
6. **Pricing-Section auf Landing-Page** — DONE, Commit 464bd13.
7. **`record_deploy` MCP-Tool + GH-Action MVP** — sobald Pro live.
   `mcp-analytics/record-deploy@v1` Action in eigenem Repo. ~3-4h.
8. **BRIEFING.md-Roadmap-Update** — Deploy-Regression als Phase-2 Item
   nachziehen. ~30min.
9. **Settings-UI für Auto-Overage opt-in** — Toggle + Stripe-Card-Setup.
   ~3h.

---

## 10. Anhang — Recherche-Trail (Mai 2026)

Drei parallele Subagent-Recherchen am 2026-05-07 plus kritische Bewertung
am gleichen Tag:

- **Privacy-Säule**: plausible.io · pirsch.io/pricing · usefathom.com/pricing
  · matomo.org/pricing · posthog.com/pricing · umami.is/pricing
  · vercel.com/docs/analytics · developers.cloudflare.com/web-analytics
  · simpleanalytics.com/pricing
- **Bot-Säule**: cloudflare.com/ai-crawl-control · datadome (G2/Capterra)
  · vercel.com/docs/botid · arcjet.com/pricing
  · humansecurity.com 2026 AI-Traffic-Report
  · netlify.com/build/user-agent-categories · pirsch.io/news (AI-Referrer)
  · brandonleuangpaseuth.com/blog/promptwatch-pricing
- **MCP-Pillar / Deploy-Regression**: blog.sentry.io/introducing-mcp-server-monitoring
  · sentry.io/pricing · langfuse.com/pricing · pulsemcp.com/statistics
  · github.com/PostHog/posthog-annotate-merges-github-action
  · launchdarkly.com/pricing · support.claude.com (Connectors-Directory-FAQ)

**Reactivate-Trigger** vor Pricing-Go-Live nochmal prüfen:
- Hat Anthropic native Connector-Analytics geshippt?
- Hat Plausible einen MCP-Wrapper als offizielles Feature gelaunched?
- Hat Cloudflare AICC zu allgemeiner Web-Analytics ausgebaut?
- Ist Sentry Ruby-MCP-SDK aus Beta?

Wenn eines eintritt → Wedge muss neu begründet werden.
