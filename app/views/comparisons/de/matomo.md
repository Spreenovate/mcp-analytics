---
competitor: "Matomo"
competitor_url: "https://matomo.org"
slug: matomo
title: "mcp-analytics vs Matomo (2026)"
description: "Matomo ist das Heatmaps/A-B/Recordings-Tool für DSGVO-bewusste Teams. Wir sind fokussiertes MCP-natives Web-Analytics. Wo welches gewinnt."
date: 2026-05-19
verdict_us: "MCP-nativ. Du fragst in Claude/ChatGPT/Cursor, du bekommst eine Antwort. Free 100k Hits/Mo ohne Karte. Bot-/AI-Crawler-Taxonomie. Best fit: Indie SaaS und Content-Sites, die schnell und ohne Ballast Stats wollen."
verdict_them: "Die DSGVO-Premium-Suite. Heatmaps, Session-Recordings, A/B-Tests, Form-Analytics, alles zentral. Best fit: Marketing-Teams, die genau diese erweiterten Funktionen brauchen und einen €29-€199/Mo-Budget haben."
table:
  - feature: "Preis-Einstieg"
    us: "Free 100k Hits/Mo, keine Karte.\n€19/Mo für 10M Hits."
    them: "21-Tage-Trial, kein Free.\n€29/Mo Essentials für 50k Hits."
  - feature: "Hits bei ~€29"
    us: "10.000.000 / Monat (für €19)"
    them: "50.000 / Monat"
  - feature: "Open Source"
    us: "Proprietär."
    them: "Ja, GPL. Selbst-hostbar (eigene Story als Matomo On-Premise)."
  - feature: "Dashboard UI"
    us: "Keine. MCP-only."
    them: "Volles Dashboard mit Heatmaps, Recordings, A/B-Tests, Forms-Analytics."
  - feature: "MCP-Server"
    us: "Ja, primäres Interface. 23 Tools."
    them: "Nein."
  - feature: "EU-Hosting"
    us: "Hetzner Falkenstein."
    them: "Frankreich (Cloud) oder selbst-gehostet."
  - feature: "Heatmaps / Session-Replay"
    us: "Nein."
    them: "Ja, Premium-Feature."
  - feature: "A/B-Testing"
    us: "Nein."
    them: "Ja, integriert."
  - feature: "Cookielos"
    us: "Ja (Strict-Modus)."
    them: "Konfigurierbar; Default mit Cookies."
  - feature: "Custom Events"
    us: "JS + Server-Side-SDK auf Pro."
    them: "JS- und API-basiert."
  - feature: "AI-Crawler-Taxonomie"
    us: "8 Traffic-Klassen inkl. ai_user_action, ai_crawler."
    them: "Bots werden gefiltert; AI-Referrer als Channel verfügbar."
---

Matomo ist die DSGVO-Premium-Suite. Open-source seit 2007, GPL-lizenziert, mit Heatmaps, Session-Recordings, A/B-Tests, Form-Analytics. In Frankreich gehostet, selbst-hostbar als On-Premise. Sie haben sich im EU-Markt einen Namen gemacht als die "Privacy-konforme GA-Alternative mit allen Features."

mcp-analytics ist eine ganz andere Wette. Wir sind fokussiertes Web-Analytics mit MCP-Primärinterface. Wenn du auch nur ein paar von Matomos Premium-Features brauchst (Heatmaps, Recordings, A/B), sind wir nicht dein Tool. Wenn nicht, lies weiter.

## Wo Matomo gewinnt

**Premium-Features**, die wir nie haben werden:

- **Heatmaps** zeigen dir, wo Nutzer klicken
- **Session-Recordings** lassen dich Nutzer-Sessions abspielen
- **A/B-Tests** mit integriertem Builder
- **Form-Analytics** (welche Formularfelder Nutzer abbrechen)
- **Tag-Manager** (Matomo Tag Manager als Alternative zu Google Tag Manager)

Wir bieten null davon. Wir werden es nicht bauen. Das ist eine separate Produkt-Kategorie. Wenn du diese Features brauchst, ist Matomo die richtige Wahl, Punkt.

**Open Source.** GPL-lizenziert, selbst-hostbar. Wenn deine Compliance-Anforderungen oder operative Präferenz "Code auf eigenen Servern" sind, geht das mit Matomo, nicht mit uns.

**Mature.** Matomo gibt es seit 2007 (damals als Piwik). Sie haben durch jede DSGVO-Iteration und jede Heat-Map-Tool-Evolution hindurch geliefert. Vertrauenssignal.

**EU-Hosting (Frankreich) oder selbst-gehostet.** Beide EU-Optionen. Wir sind nur Hetzner Falkenstein.

**Free On-Premise.** Wenn du selbst hostest, ist Matomo kostenlos. Cloud kostet, On-Premise nicht (nur deine Server-Kosten).

## Wo mcp-analytics gewinnt

**Free Cloud-Tier ohne Karte.** Matomo Cloud hat 21 Tage Trial, dann €29/Mo. Wir haben 100k Hits/Mo free, unbegrenzte Sites, alle 23 MCP-Tools, keine Karte.

**Volumen-Headroom**. Matomos €29-Tier ist 50k Hits/Mo, wir bei €19 sind 10M Hits/Mo. Faktor 200. Wenn dein Traffic spikt (Newsletter, Hacker News, viraler Tweet), trifft dich Matomos Cap an einem einzigen guten Tag.

**MCP-Primärinterface.** Das ganze Produkt. Du fragst "Wie lief letzte Woche?" in Claude oder ChatGPT, du bekommst einen Satz zurück. Matomo hat eine API, kein Chat-Interface.

```
Du: "Top-Pages letzte 7 Tage auf mysite.com, was ist neu?"
Claude: "Drei neue Top-Pages diese Woche: /blog/llms-txt-explained
        (847 Views, kam Donnerstag rein), /docs/setup (412), und
        /vs/google-analytics (289). Hauptreferrer für die llms-Page
        ist X.com, ein Thread vom Mittwoch."
```

**AI-Crawler-Sicht.** Matomo zeigt AI-Referrer (Mensch aus ChatGPT/Perplexity), wir zusätzlich AI-Crawler selbst (GPTBot, ClaudeBot, etc.). Die werden 2026 zur eigenständigen Traffic-Quelle, die du tracken willst.

**Server-Side-Events.** Unser Ingest-Endpoint nimmt `POST /event` direkt entgegen für Backend-Events. Erst-Party Ruby-Gem und npm-Wrapper sind auf der Pro-Roadmap. Matomo hat eine Tracking-API, aber kein dediziertes Server-Side-Event-Pattern.

**Schlankheit.** Matomo ist ein großes Produkt mit vielen Features, was Setup-Zeit und Onboarding-Aufwand bedeutet. Wir sind klein. Snippet einbauen, in Claude fragen, fertig.

## Wann du Matomo nehmen solltest

- Du brauchst Heatmaps, Session-Recordings, A/B-Tests oder Form-Analytics.
- Open Source ist dir wichtig (selbst-hostbar).
- Du arbeitest in einem Marketing-Team und brauchst die volle Suite an einem Ort.
- Du hast €29-199/Mo Budget für das Tool und brauchst die Premium-Features.

## Wann du uns nehmen solltest

- Du verbringst Stunden täglich in Claude/ChatGPT/Cursor.
- Du willst Free, das du langfristig nutzen kannst, ohne Karte.
- Dein Traffic könnte spiken. 200x mehr Headroom bei vergleichbarem Preis.
- Du brauchst AI-Crawler-Aufschlüsselung, kein stilles Filtern.
- Du brauchst Server-Side-Event-Tracking aus deinem Backend.

## Was kein echter Unterschied ist

- Beide DSGVO-tauglich aufstellbar.
- Beide cookielos-fähig (Matomo opt-in, wir Default-Strict).
- Beide unterstützen Custom Events.

## Migration

Beide lassen sich parallel betreiben. Unser Snippet kollidiert nicht mit Matomos. Häufiges Muster: Matomo bleibt für Heatmaps/Recordings auf der Marketing-Site, wir kommen auf Side-Projects und interne Tools, wo der Chat-Workflow schneller ist.

## Loslegen

[Free anmelden](/), 100k Hits/Mo, keine Karte.

Spezifisches Matomo-Feature, von dem du nicht weglassen willst? [Email uns](mailto:hello@mcp-analytics.com). Wir sagen direkt, ob wir's haben oder Matomo dein bleibendes Tool sein muss.
