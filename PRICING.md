# PRICING.md — Vorschlag, Mai 2026

Working-Doc parallel zu `BRIEFING.md`. Ziel: ein Pricing, **das standhält**
gegen Plausible/Fathom/Pirsch (Privacy-Analytics-Floor), Cloudflare AI Crawl
Control (Bot-Traffic-Floor) und Sentry MCP Monitoring (zweite Säule).
Subagent-Recherche siehe Anhang am Ende.

Struktur:

1. [Markt-Landkarte](#markt-landkarte) — wer für was wieviel nimmt
2. [Eigene Kostenbasis](#eigene-kostenbasis)
3. [Wedge & Defensible-Positionierung](#wedge--defensible-positionierung)
4. [Pricing-Vorschlag](#pricing-vorschlag)
5. [Warum das hält](#warum-das-hält) — Konkurrenz-Matrix
6. [Roadmap-Mapping](#roadmap-mapping) — wann welches Feature welchen Tier rechtfertigt
7. [Risiken & offene Fragen](#risiken--offene-fragen)
8. [Implementierungs-Followups](#implementierungs-followups)

---

## Markt-Landkarte

### Säule 1 — Privacy-first Web-Analytics (direkter Wettbewerb)

| Player                | Free-Tier              | Erster Paid-Step              | Sites    | Retention   | Bemerkung                                                  |
|-----------------------|------------------------|-------------------------------|----------|-------------|------------------------------------------------------------|
| **Plausible**         | keiner (30d Trial)     | $9/Mo · 10k pv                | 1        | 3 J         | Open-Core-Halo, EU. Kein Free → unser Acquisition-Vorteil. |
| **Pirsch**            | 30d Trial              | **$6/Mo · 10k pv**            | 50       | unbegrenzt  | DE-hosted, billigster credible EU. Direktester Konkurrent. |
| **Fathom**            | 30d Trial              | $15/Mo · 100k pv              | 50       | forever     | Premium-UX-Brand, "unlimited sites" als Hook.              |
| **Simple Analytics**  | 5 Sites, 30d           | $15/Mo · 20k Datenpunkte      | 10       | 3 J         | Hat reales Free → eines der wenigen.                       |
| **Umami Cloud**       | **1M events/Mo**       | ~$20/Mo Pro                   | viele    | 6 Monate    | Dickste Free-Decke. Open-Source.                           |
| **GoatCounter**       | unlimited (personal)   | $5/Mo (≈100k pv)              | viele    | unbegrenzt  | Hobby-Floor. Single-Maintainer, kein Brand-Risk-Player.    |
| **Cloudflare WA**     | gratis                 | —                             | viele    | 30d         | 10% gesampelt + Top-15-Cap. Marketing-Free, kein Produkt.  |
| **Vercel WA**         | Hobby (capped)         | $10/Mo Plus-Add-on            | viele    | 30d         | Vercel-Lock-in. Egal für unsere Zielgruppe.                |
| **PostHog**           | 1M events/Mo           | volume-based ab $0.00005/event| viele    | 1 J         | Suite, nicht Plausible-Form. Free ist gefährlich generös.  |
| **Matomo Cloud**      | 21d Trial              | **€29/Mo · 50k Hits**         | 30       | flexibel    | Premium-Anker. Heatmaps/A-B/Recordings rechtfertigen €29.  |
| **Tinybird Template** | Build-Plan free        | $25/Mo Developer              | DIY      | DIY         | Kein Produkt, ein Bauklotzkasten. Stack-Spiegel.           |

**MCP-native Indie-Player:** GitHub-only Wrapper (alexanderop, AVIMBU,
The-Focus-AI) — alles dünne Plausible-API-Proxies, niemand besitzt den
Ingest. **Keine kommerzielle MCP-native Privacy-Analytics in 2026 live.**
Slot offen.

### Säule 2 — Bot-/AI-Agent-Traffic-Visibility (defensives Feature)

| Player                       | Tier-Einstieg           | AI-Agent-Breakdown im Einstieg?    | Was sie wirklich zeigen                                  |
|------------------------------|-------------------------|------------------------------------|----------------------------------------------------------|
| **Cloudflare AI Crawl Ctrl** | **Free (CF-Free-Plan)** | Ja, UA-basiert; Pro/Bus = Sig-Verif | Per-Crawler-Hits, Pay-Per-Crawl-Beta. Nur was via CF läuft. |
| **DataDome**                 | $3,830/Mo               | Ja                                 | Enterprise. Nicht unser Markt.                           |
| **HUMAN/Imperva/Akamai**     | $1k–$50k+               | Ja                                 | Enterprise. Nicht unser Markt.                           |
| **Vercel BotID**             | Free auf allen Plans    | Teilweise (Firewall-Logs)          | $1/1k Deep-Analysis-Calls auf Pro+. Vercel-Lock.         |
| **Arcjet**                   | $25/Mo Individual       | Schutz-first, keine Aggregation    | SDK-style, dev-first. Kein per-Bot-Pageview-Report.      |
| **Plausible/Fathom/Pirsch**  | siehe oben              | **Nein** (Bots werden gefiltert)   | Pirsch hat AI-Referrer-Channel — also Mensch-aus-ChatGPT, NICHT Crawler. |
| **Promptwatch**              | $99/Mo · 2 Sites        | Ja, primary product                | Dichtester Indie-Konkurrent. Site-Cap ist ihr Achilles.  |
| **Known Agents**             | $10–30/Mo               | Teilweise                          | robots.txt-Automation primary, Analytics secondary.      |
| **Netlify**                  | bundled                 | Ja (Netlify-Agent-Category Header) | Nur Netlify-Hostings.                                    |

**Erkenntnis:** Im Indie-Preisband ($10–30) gibt es **niemanden**, der
Server-Side-Hybrid-Tracking (Origin-Middleware) + AI-Agent-Taxonomie +
MCP-native zusammen anbietet. Cloudflare deckelt nur, *wenn der Kunde auf
CF ist* — der ganze WordPress/Rails/Node/static-host-Long-Tail bleibt
übrig. Das ist unser Wedge bis ~12 Monate.

### Säule 3 — MCP-Server-Analytics (zweite Säule, "Plausible für MCP-Server")

| Player                  | Was sie für MCP-Autoren liefern             | Pricing                | Indie-tauglich? |
|-------------------------|---------------------------------------------|------------------------|-----------------|
| **Sentry MCP Monitor**  | `wrapMcpServerWithSentry()` — pro-Tool: Req/Err/Latenz/Client-Mix | Free 5k Errors + 10k Perf, Team $26/Mo | **Hoch — direkteste Bedrohung.** JS-first. Ruby-SDK fehlt. APM-shaped, nicht Analytics-shaped. |
| **Datadog AI-Obs**      | Tiefste MCP-Client-Tracing-Coverage         | $31/Host/Mo + AI-Obs   | Nein.           |
| **Grafana + OpenLIT**   | `openlit.init()` autoinstrument MCP         | Cloud-Free + DIY       | DIY-Schmerz.    |
| **Langfuse**            | End-to-end MCP-Tracing                      | Free 50k events, $29 Core, $199 Pro | Trace-shaped, nicht Site-Analytics-shaped. |
| **LangSmith / Helicone**| LLM-Trace-shaped                            | LangChain-/Proxy-Lock  | Nein.           |
| **Smithery / Glama / mcp.so / PulseMCP** | Registry/Host. **Keine Autoren-Analytics** veröffentlicht | N/A          | —               |
| **Anthropic**           | **Nichts.** Connectors-Directory-FAQ punted explizit auf Drittanbieter. | —    | —               |

**Erkenntnis:** Slot offen. Sentry hat den einzigen einzeiligen Wrapper,
ist aber JS + APM-Schmerz-shaped. ~10–17k öffentliche MCP-Server existieren
(PulseMCP-Statistik), <5% kommerziell ernsthaft → realistische SAM ~1–2k
zahlende Autoren. Plausible-Ladder $9/$29 funktioniert.

### Säule 4 — Deploy-Regression-Detection (Bundle-Feature, kein eigenes SKU)

| Player                  | Was sie korrelieren                                          | Pricing                          |
|-------------------------|--------------------------------------------------------------|----------------------------------|
| **PostHog**             | Threshold/Anomalie-Alerts auf jedes Insight + GH-Action für Annotations | Generös free, dann volume        |
| **Sentry Releases**     | Error-Rate, regressed-issues-by-release-tag                  | Bundled in Team $26/Mo           |
| **LaunchDarkly Guardian** | Auto-Release-Monitoring + Auto-Rollback                    | $12/svc + $10/1k MAU, Top-Tier   |
| **Datadog Watchdog**    | Faulty-Canary, Code-Version-Diff                             | $31/Host APM-Minimum             |
| **Vercel + Statsig**    | Native Vercel-Integration, Edge-Flag-Eval                    | Vercel-Lock                      |
| **Plausible**           | **Keine Annotations-API**, keine Deploy-Awareness in Produkt  | —                                |

**Erkenntnis:** Niemand schippt das exakte Rezept "GH-Action →
`record_deploy` MCP-Tool → `regression_check` MCP-Tool, in Claude
abrufbar". PostHog hat die Annotation-Action, aber ohne MCP-Loop. **Als
Standalone-Feature commodity, als MCP-Wedge an unser Ladder gebunden:
einzigartig.** → Bundle-Feature, kein eigenes Tier.

---

## Eigene Kostenbasis

Stand-Stack auf einer Hetzner CX32 in Falkenstein:

| Position                                       | EUR/Mo  | Bemerkung                                    |
|------------------------------------------------|---------|----------------------------------------------|
| Hetzner CX32 (4 vCPU, 8 GB, 80 GB SSD)         | ~7.50   | inkl. 20 TB Egress                           |
| Backup-Volume                                  | ~2.00   | täglicher `ops/backup.sh` an Hetzner-Storage |
| Postmark / SES (transaktional)                 | ~5.00   | Verify-Mails, Operator-Alerts                |
| Domain + DNS                                   | ~2.00   |                                              |
| GHCR Image Hosting                             | 0       | Kostenfrei via GitHub                        |
| **Summe Infra-COGS (single host)**             | **~17** | Bis ~5k aktive Sites tragbar                 |

ClickHouse-Storage-Tagebuchrechnung: 100k events ≈ 10 MB komprimiert.
1M events/Site/Monat × 1k zahlende Indies = 1B events/Monat ≈ 100 GB/Monat
(unkomprimiert ~10x mehr) — die CX32 fasst das einige Monate, danach
zweite CX32 als ClickHouse-Reader-Replica oder CX42-Upgrade (€14/Mo).

**Wichtig fürs Pricing:** unsere COGS-Skalierungskurve ist *flach* bis ~1k
Paid-User. Plausible/Fathom/PostHog haben Dashboard-Frontend-Personalkosten,
wir bewusst nicht. Das ist unser Pricing-Vorteil — wir können die ersten
1000 Kunden mit ≤€100/Mo Infra bedienen.

---

## Wedge & Defensible-Positionierung

**Vier Differentiatoren, die zusammen niemand sonst hat:**

1. **MCP-native primary interface.** Kein Dashboard zu unterhalten,
   keine Frontend-Devs, keine Charts-Library. Die "Antwort" ist Claude.
   Plausible kann das nie nachbauen ohne eigene Brand zu kannibalisieren.
2. **Server-side Hybrid-Ingestion** (Phase 4 Roadmap). Ruby-Gem +
   Node-Middleware fängt JS-blinde Crawler. Plausible/Fathom/Pirsch sind
   strukturell JS-only und können das nicht nachrüsten ohne ihren Stack
   umzubauen.
3. **Bot-/AI-Agent-Taxonomie auf View-Ebene** (Roadmap-Phase 1 done,
   2-4 todo). Pirsch hat AI-Referrer (Mensch aus ChatGPT) — das ist nicht
   das Gleiche. Wir zeigen *Crawler*-Sicht.
4. **Zwei-Säulen-Bundle:** Web + MCP-Server-Analytics auf einem Account.
   Sentry deckt Säule 2 ab (APM-Brand), Plausible deckt Säule 1 ab
   (Privacy-Brand). Niemand bündelt — unser Cross-Sell-Hebel.

**Was *nicht* differenziert** (also bitte nicht draufpreisen):

- **EU-Hosting / GDPR-clean.** Tablestakes 2026, Pirsch hat das, Matomo
  hat das, Plausible hat EU-Region. Erwähnen, aber nicht damit Premium
  rechtfertigen.
- **Open-Source-Halo.** Plausible besetzt das. Wir sind proprietär — bitte
  nicht versuchen, es ihnen abzunehmen.
- **Lifetime-Deals.** Tot in 2026, niemand fährt sie mehr. Ignorieren.

---

## Pricing-Vorschlag

Vier Tiers + Add-ons. Currency EUR (Hauptmarkt EU, Hetzner zahlt EUR,
SEPA-Friction-frei).

### Hobby — **Free forever**

- **1 Mio. Hits/Monat**, fair-use (heutiger Cap ist 100k → **bumpen auf 1M**, siehe unten Begründung)
- **Unlimited Sites**
- 1 Jahr Retention
- Alle 18 MCP-Analytics-Tools
- Strict-/default-/all-Privacy-Modi
- 1 Bridge-Account (1 OAuth-Connector)
- Community-Support (GitHub Issues, kein E-Mail-Support)

**Begründung Free-Bump 100k → 1M:** Plausible/Fathom/Pirsch geben **null**
free, Umami/PostHog geben 1M. Wenn wir bei 100k bleiben sind wir das
"großzügige Premium-Trial", bei 1M sind wir das "ehrliches Indie-Werkzeug".
Bei einer COGS-Kurve die so flach ist wie unsere kostet uns das praktisch
nichts und akquiriert maximal. Der ehrliche Forcing-Function für Upgrade
ist nicht Volumen sondern **Features** (Bot-Taxonomie, MCP-Server-Pillar,
Deploy-Hook, Team-Seats).

### Indie — **€9/Mo** (€90/Jahr = 2 Monate gratis)

Zielgruppe: Solo-Dev mit 1–5 Projekten, der monatlich für sein Tooling
zahlt. Direkt-positioniert gegen Plausible $9/10k.

- **10 Mio. Hits/Monat**
- **Bot-/AI-Agent-Traffic-Taxonomie** (Phase-2-Cloudflare-kompatible Klassen)
- **Server-side Ingestion-SDK** (Ruby-Gem, Node-Middleware, Pixel-Endpunkt) — fängt JS-blinde Crawler
- **Deploy-Regression-Bundle:** GH-Action `record_deploy` + MCP-Tools `record_deploy`/`regression_check`
- **MCP-Server-Analytics-Pillar (1 Server, 100k Tool-Calls/Mo)** — Ruby-Gem `mcp-analytics-rack` + Node-SDK, Tools `top_mcp_tools`, `mcp_clients_breakdown`, `mcp_errors`, `mcp_latency_distribution`
- 3 Jahre Retention
- E-Mail-Support, 24h-Antwort
- 1 Bridge-Account

### Studio — **€29/Mo** (€290/Jahr)

Zielgruppe: kleines Team / Indie-Agency / commercial Indie-Hacker mit
mehreren Properties. Direkt-positioniert gegen Fathom $15/100k und
Promptwatch $99/2 Sites.

- **100 Mio. Hits/Monat**
- Alles aus Indie, plus:
- **MCP-Server-Pillar Studio:** bis zu 10 MCP-Server, 1 Mio. Tool-Calls/Mo
- **Web-Bot-Auth-Signaturverifikation** (Phase-3-Roadmap, sobald live) — verifizierte vs. spoofed Agents getrennt
- **Verifizierte AI-Crawl-Belege** als Marketing-belastbare Zahl ("23 verifizierte ClaudeBot-Fetches diese Woche")
- 5 Jahre Retention
- **Team-Seats: 5** (jeder mit eigenem OAuth-Token + scope-isoliert)
- **Custom-Webhook** für Hit-Events (post-MVP)
- Priority-E-Mail-Support, 12h-Antwort

### Enterprise — **ab €299/Mo, custom**

Zielgruppe: high-Traffic-Sites, regulierte Branchen, MCP-Plattform-Anbieter
(Smithery/Glama-Wettbewerber die Whitelabel wollen).

- Dedizierter Hetzner-Host (CX42 oder größer, single-tenant ClickHouse)
- **`query_sql` Power-Tool** — direktes SQL gegen die eigene ClickHouse
- DPA, SLA 99.9%, Audit-Log, SAML/SSO
- Custom-Retention (bis 7 J), custom Tracking-Domain, White-Label-Skript
- Onboarding-Call + dedicated Slack-Connect
- Konkretes Pricing per Engagement; vorhandener `enterprise@mcp-analytics.com`-Funnel bleibt

### Add-ons (alle Tiers)

| Add-on                                          | Preis              | Begründung                                      |
|-------------------------------------------------|--------------------|-------------------------------------------------|
| **Verified-Bot-Signature-Belege**               | €0.01 / 1k Fetches | Cloudflare-Pay-Per-Crawl-Analogon. Marketing-Premium-Story. |
| **Extra MCP-Server-Tool-Calls** (über Tier-Cap) | €1 / 100k          | unter Sentry-Niveau, hält Friction klein.       |
| **Extra Hits** (über Tier-Cap)                  | €0.50 / 100k       | unter Plausible-Marge.                          |
| **Open-Source-Project-Plan**                    | Studio gratis      | Bedingung: README-Badge "powered by mcp-analytics", öffentliches GH-Repo. Distribution-Hebel. |
| **Annual-Prepay**                               | -16%               | 2 Monate gratis = saubere Kommunikation.        |

---

## Warum das hält

Konkurrenz-Matrix (X = besser-als-wir, ✓ = gleich, **fett** = wir gewinnen):

| Konkurrent          | Tier             | Hits/Mo   | Sites    | Bot-Taxo | Server-Side | MCP-native | Deploy-Regr | EU      | Preis   |
|---------------------|------------------|-----------|----------|----------|-------------|------------|-------------|---------|---------|
| **Plausible**       | $9 Starter       | 10k       | 1        | nein     | nein        | nein       | nein        | ✓       | $9      |
|                     | wir Hobby        | **1M**    | **∞**    | nein     | **ja**      | **ja**     | nein        | ✓       | **0**   |
| **Pirsch**          | $6 Standard      | 10k       | 50       | Referrer | nein        | nein       | nein        | ✓       | **$6**  |
|                     | wir Hobby        | **1M**    | ✓        | nein     | **ja**      | **ja**     | nein        | ✓       | **0**   |
| **Fathom**          | $15 Entry        | 100k      | 50       | nein     | nein        | nein       | nein        | ✓       | $15     |
|                     | wir Indie        | **10M**   | ✓        | **ja**   | **ja**      | **ja**     | **ja**      | ✓       | **€9**  |
| **Umami Cloud**     | Free             | 1M        | viele    | nein     | nein        | nein       | nein        | ✓       | ✓       |
|                     | wir Hobby        | ✓         | ✓        | nein     | **ja**      | **ja**     | nein        | ✓       | ✓       |
| **Cloudflare AICC** | Free (CF)        | unlimited | nur CF   | **ja**   | nein (CDN)  | nein       | nein        | nein    | ✓       |
|                     | wir Indie        | 10M       | ✓        | ✓        | **ja**      | **ja**     | **ja**      | **ja**  | €9      |
| **Promptwatch**     | $99 Essential    | ?         | 2        | ja       | ?           | nein       | nein        | nein    | $99     |
|                     | wir Studio       | 100M      | **∞**    | ✓        | **ja**      | **ja**     | **ja**      | **ja**  | **€29** |
| **Sentry MCP Mon**  | $26 Team         | n/a       | n/a      | n/a      | n/a         | wrapper    | nein        | mixed   | $26     |
|                     | wir Indie        | **+web**  | n/a      | **ja**   | **ja**      | **deeper** | **ja**      | **ja**  | **€9**  |

**Drei strukturelle Gründe warum das nicht unterboten wird:**

1. **Plausible/Fathom/Pirsch können den Free-Tier nicht matchen** ohne ihr
   Pricing-Modell zu sprengen — sie haben Frontend-COGS, wir nicht. Wenn
   sie es trotzdem versuchen (Plausible hat 30d-Trial von "free forever"
   schonmal probiert und zurückgezogen), rebranden wir auf MCP+SDK-Sale
   und lassen die Web-Analytics-Säule bei Acquisition-Loss laufen.

2. **Cloudflare AI Crawl Control deckelt uns nur für CF-Kunden.** Der
   gesamte Long-Tail (WordPress-on-shared-host, Rails-on-Hetzner,
   Static-on-Netlify-without-CF, …) bleibt ungelöst. Wir müssen das in der
   Landing-Page nicht ignorieren — *adressieren*: "schon auf Cloudflare?
   nutz deren AI Crawl Control, ist gratis. Nicht? Dann sind wir dein
   Origin-Sniffer."

3. **Sentry-MCP-Monitoring ist APM-shaped, wir sind Analytics-shaped.**
   Sentry will Errors-First-Buyer (Production-On-Call). Wir wollen
   Build-Audience-Buyer (Indie-Hacker mit MCP-Server auf Smithery). Selbe
   Daten, andere Frage, andere Buyer. Sie können unsere "wer benutzt mein
   MCP-Tool?"-Frage nicht ohne neues SKU beantworten.

**Was uns *kippen* könnte (ehrlich):**

- Anthropic shipped first-party MCP-Connector-Analytics (im Connectors-
  Directory). Heute punted die FAQ explizit, kann morgen ändern. → Pillar
  3 ist preempt-anfällig.
- Plausible kauft eine MCP-Wrapper-Brand und shipt es als Pro-Feature für
  $19. Hard-to-counter; Mitigation = unser Hobby-Free + bidirektionale
  Bot-Taxonomie-Wedge halten.
- Cloudflare schnappt Server-Side-Origin-Tracking auf (CF-Workers-AI-
  Crawl-Sniffer für Origin). Realistisch in ~12-18 Monaten. → unser
  Phase-4-Push muss diesen Sommer fertig.

---

## Roadmap-Mapping

Welches Roadmap-Feature welchen Tier rechtfertigt:

| Roadmap-Feature                                       | Stage    | Tier wo es freischaltet | Pricing-Begründung              |
|-------------------------------------------------------|----------|--------------------------|---------------------------------|
| Bot-Phase 1 — binary `traffic_class` + raw UA         | DONE     | alle (auch Hobby)        | Tablestakes, kein Differentiator |
| Bot-Phase 2 — Cloudflare-kompat. Taxonomie            | TODO     | **Indie**                | Erste echte Konkurrenz-zu-CF-AICC-Bewegung — paid-Wert |
| Bot-Phase 3 — Web Bot Auth Signature                  | FUTURE   | **Studio**               | "Verifiziert" ist Premium-Marketing-Story |
| Bot-Phase 4A Pixel-Endpoint                           | TODO     | alle                     | Static-Site-Fallback, gratis    |
| Bot-Phase 4B Ruby-Gem Middleware                      | TODO     | **Indie**                | "fängt alle Crawler" = primary Indie-Verkaufsargument |
| Bot-Phase 4C Node/Next-Middleware                     | TODO     | **Indie**                | s.o.                            |
| Bot-Phase 4D CF-Worker / Vercel-Edge                  | TODO     | **Studio**               | sucht heavy-Traffic-Kunden      |
| `record_event` Server-Side-Tool                       | TODO     | alle                     | Kleine Lücke — gratis machen    |
| MCP-Usage-Analytics (Selbst-Tracking)                 | TODO     | **Studio**               | Team-Audit-Trail = DSGVO-Pflicht für Teams |
| MCP-Server-Analytics-Pillar (Plausible-für-MCP)       | TODO     | **Indie** (1 Server) → **Studio** (10 Server) → **Enterprise** (∞) | Die zweite Säule, gestaffelt    |
| Deploy-Regression GH-Action + Tools                   | TODO     | **Indie**                | Wedge-Bundle, nicht standalone — bringt Indies in den Paid-Funnel |
| MaxMind Geo-Lookup                                    | TODO     | **Studio**               | Klassisches Premium-Feature, alle Konkurrenten machen das so |
| `query_sql` Power-Tool                                | TODO     | **Enterprise**           | Wie im Briefing schon vorgesehen |
| Self-hosted Tracker / Custom-Tracking-Domain          | TODO     | **Enterprise**           | Adblock-Workaround = großer Site-Schmerz |
| Team-Accounts                                         | TODO     | **Studio** (5 Seats) → **Enterprise** (∞) | Klassische Seat-Staffelung |
| Connector-Directory-Listing (Anthropic)               | TODO     | alle                     | Distribution, kein Tier-Differentiator |

**Roadmap-Lücke die der User explizit reingeworfen hat ("gh actions um deploys zu kontrollieren"):**
existierende Roadmap erwähnt es nicht. Empfehlung: in `BRIEFING.md`
nachziehen als **Phase-2-Feature**, ~3-4h Aufwand:

```ruby
# neue MCP-Tools
record_deploy(commit_sha, env, started_at, ended_at)
regression_check(period: "1h", baseline: "p7d_same_hour")
# returns: signups_delta_pct, error_pages_delta_pct, top_regressed_paths
```

Plus eine offizielle GH-Action `mcp-analytics/record-deploy@v1` die in
~3 Zeilen YAML einbindbar ist. Standalone commodity (PostHog macht's
free), aber als MCP-Loop einzigartig + ein Indie-Tier-Reason-to-Upgrade.

---

## Risiken & offene Fragen

1. **Free-Tier-Bump 100k → 1M ist aggressiv.** Begrenzungs-Idee falls
   Misuse: "1M *user-Klassifiziert*, Bots zählen separat aufs Hobby-Cap."
   Dann sehen Power-User schnell, dass Bot-Sicht hinter Indie liegt — sauberer Pull.

2. **MCP-Server-Pillar Cold-Start.** ~10–17k öffentliche MCP-Server, aber
   <5% kommerziell. Realistischer Markt zum Launch: ~50–200 zahlende
   Autoren in Jahr 1. → Pillar 2 nicht überinvestieren bis Pillar 1 self-sustaining ist (Briefing-Reihenfolge stimmt: erst 50 zahlende Web-Analytics-User, dann MCP-Pillar).

3. **Stripe-Friction.** Briefing-§ EXPLIZIT NICHT IM MVP enthält "Stripe".
   Wenn wir Indie-Tier €9 starten, brauchen wir Stripe Checkout +
   einen `subscriptions`-Table + Tier-Enforcement im
   `Mcp::AuthContext`. Aufwand ~1–2 Tage. Vor Pricing-Go-Live nötig.

4. **Lemon Squeezy als Alternative zu Stripe** für EU-VAT-Handling
   (EU-Merchant-of-Record). Bei <€100k MRR ist deren Gebühr (5% + 50ct)
   kleiner als der eigene VAT-Compliance-Aufwand.

5. **Free-Tier-Abuse.** Heute ist `register_account` 3/IP/h gerate-limited;
   bei "1M free" werden Scraper das als Backend-Speicher missbrauchen
   wollen. Mitigation: phone-number-required-on-signup *ab* Studio?
   Oder: free behält 1M-Cap, aber **MCP-Tool-Calls/Tag** sind auf z.B. 200
   gedeckelt — Speicher ist billig, MCP-Antwort-Tokens sind teuer für uns.

6. **Pricing-Kommunikation.** "Hobby Free, Indie €9, Studio €29" ist
   3-Tier — Plausible-Standard. Wir sollten nicht in Tier-Vergleichs-
   Tabellen-Hölle abrutschen — Landing-Page bleibt brutalistisch, eine
   `<table class="pricing">` mit 4 Spalten (Free/Indie/Studio/Enterprise),
   keine 12-Zeilen-Feature-Liste.

---

## Implementierungs-Followups

In Reihenfolge (jeweils einseitige PRs):

1. **Roadmap-Update in `BRIEFING.md`** — Deploy-Regression-GH-Action +
   `record_deploy`/`regression_check` MCP-Tools als Phase-2-Item. ~30min.

2. **`subscriptions` Modell + Tier-Enforcement** in `Mcp::AuthContext`.
   Einzelnes `User#tier` enum (`hobby`/`indie`/`studio`/`enterprise`).
   Tools schalten Features anhand `tier`. ~1 Tag.

3. **Stripe oder Lemon-Squeezy-Checkout** integration.
   `/upgrade/:tier` endpoint, Webhook in `SubscriptionsController#sync`.
   ~1 Tag.

4. **Hits-Cap-Soft-Enforcement** umstellen: heute ist's "Warning + Hinweis"
   bei 100k. Bei 1M wird's "Bots zählen separat ab Indie-Tier" — UI in
   `get_overview` muss das kommunizieren ("Bot-Sicht ab Indie verfügbar").

5. **Pricing-Section auf Landing-Page** (`app/views/pages/home.html.erb`)
   einbauen — 4 Spalten brutalistisch, Free–Indie–Studio–Enterprise.

6. **`record_deploy` + GH-Action MVP** (~3-4h) — sobald Indie-Tier live ist.

7. **MCP-Server-Pillar SDK-Skelett** — Ruby-Gem `mcp-analytics-rack`
   in eigenem Repo, MIT-Lizenz für Distribution. ~1 Woche MVP.

---

## Anhang — Subagent-Recherche (Mai 2026, archiviert)

Drei parallele Recherchen liefen am 2026-05-07. Roh-Reports einsehbar
in den Session-Logs (`af0c8d9b…`, `af5817a9…`, `a241b498…`). Wesentliche
Quellen:

- **Privacy-Säule:** plausible.io · pirsch.io/pricing · usefathom.com/pricing · simpleanalytics.com/pricing · matomo.org/pricing · posthog.com/pricing · umami.is/pricing · vercel.com/docs/analytics/limits-and-pricing · developers.cloudflare.com/web-analytics/limits · tinybird.co/pricing
- **Bot-Säule:** cloudflare.com/ai-crawl-control · datadome (G2/Capterra) · vercel.com/docs/botid · arcjet.com/pricing · humansecurity.com 2026 AI-Traffic-Report · netlify.com/build/user-agent-categories · pirsch.io/news (AI-Referrer-Channel) · brandonleuangpaseuth.com/blog/promptwatch-pricing
- **MCP-Pillar / Deploy-Regression:** blog.sentry.io/introducing-mcp-server-monitoring · sentry.io/pricing · langfuse.com/pricing · grafana.com/blog/ai-observability-MCP-servers · pulsemcp.com/statistics · github.com/PostHog/posthog-annotate-merges-github-action · launchdarkly.com/pricing · statsig.com/blog/statsig-vercel-native-integration · support.claude.com/en/articles/11596036 (Connectors-Directory-FAQ)

Reactivate-Trigger: vor Pricing-Go-Live nochmal prüfen, ob:
- Anthropic native Connector-Analytics geshippt hat
- Plausible einen MCP-Wrapper als offizielles Feature gelaunched hat
- Cloudflare AI Crawl Control jetzt auch Origin-Crawl-Visibility hat (heute nur CF-traversed-Traffic)
- Sentry Ruby-MCP-SDK aus Beta gezogen ist

Wenn eines davon eintritt → entsprechender Tier-Wedge muss neu begründet werden.
