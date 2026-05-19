---
competitor: "Pirsch Analytics"
competitor_url: "https://pirsch.io"
slug: pirsch
title: "mcp-analytics vs Pirsch Analytics (2026)"
description: "Pirsch ist das günstigste glaubwürdige EU-gehostete Analytics. Wir sind MCP-nativ. Wo welches gewinnt."
date: 2026-05-19
hreflang_alt: pirsch
verdict_us: "MCP-natives Primärinterface. Free 100k Hits/Mo ohne Karte. 8-Klassen-Bot-Taxonomie. Server-Side-SDK auf Pro. Best für Claude/Cursor-Power-User."
verdict_them: "Günstigstes glaubwürdiges EU-gehostetes Analytics mit Dashboard. Eingebauter AI-Referrer-Channel. Best für deutschsprachige Founder, die ein sauberes Dashboard und kleine Rechnung wollen."
table:
  - feature: "Preis-Einstieg"
    us: "Free 100k Hits/Mo, keine Karte.\n€19/Mo für 10M Hits."
    them: "30-Tage-Trial.\n$6/Mo Standard für 10k Pageviews."
  - feature: "Hits bei ~€19"
    us: "10.000.000 / Monat"
    them: "100.000 / Monat (Plus-Tier)"
  - feature: "Dashboard UI"
    us: "Keine. MCP-only."
    them: "Polished Dashboard mit AI-Referrer-Channel eingebaut."
  - feature: "MCP-Server"
    us: "Ja, primäres Interface. 23 Tools."
    them: "Nein."
  - feature: "EU-Hosting"
    us: "Hetzner Falkenstein."
    them: "Deutschland-gehostet, DSGVO-nativ."
  - feature: "Cookielos"
    us: "Ja (Strict)."
    them: "Ja per Default."
  - feature: "Custom Events"
    us: "JS + Server-Side-SDK auf Pro."
    them: "JS-basiert."
  - feature: "AI-Crawler-/Referrer-Tracking"
    us: "8 Traffic-Klassen inkl. ai_user_action, ai_crawler, verified_search_bot."
    them: "AI-Referrer-Channel (Mensch aus ChatGPT/Perplexity). Keine Crawler-Aufschlüsselung."
  - feature: "Unbegrenzte Sites"
    us: "Ja, alle Tiers."
    them: "50 Sites Standard, mehr auf höheren Tiers."
  - feature: "Herkunft"
    us: "Spreenovate GmbH (Berlin)."
    them: "emvi Software GmbH (Hannover)."
---

Pirsch ist das günstigste glaubwürdige Privacy-first Analytics-Tool mit EU-Hosting. Kleines deutsches Team, sie haben ein tightes, schnelles Produkt gebaut. Respekt für das, was sie geliefert haben.

Pirsch und mcp-analytics sind keine direkten Substitute. Andere Interface-Wette. Die ehrliche Variante:

## Wo Pirsch gewinnt

**Preis-Floor.** Pirschs $6/Mo Standard ist das günstigste glaubwürdige EU-gehostete Analytics am Markt. Wenn du eine persönliche Site mit unter 10k Pageviews/Mo hast und das bezahlt willst (keine Karte-auf-Datei-Abhängigkeit wie bei uns auf Free), ist Pirsch günstiger. Wir sind free bis 100k, dann €19. Für eine winzige Site gewinnt Pirsch im Dollar-Vergleich.

**AI-Referrer-Channel.** Pirsch hat in seinem Dashboard einen "AI"-Channel, der Referrer von ChatGPT, Perplexity, Claude.ai etc. zusammenfasst. Also menschliche Besucher, die aus einem AI-Chat klicken. Nützlicher vorgebauter Filter. Wir tracken dieselben Daten (in `top_referrers`), aber wir haben keine UI-Gruppierung dafür, weil wir keine UI haben. Du würdest im Chat fragen "Wie viel des Traffic kam letzte Woche aus AI-Referrern?".

**Polished Dashboard.** Pirschs Dashboard ist sauber, schnell, deutsch-engineered. Wenn du ein Dashboard willst, ist Pirschs gut. Wir haben keins.

**Same-Country-Hosting.** Pirsch ist in Deutschland gehostet (Hannover). Wir sind in Deutschland gehostet (Falkenstein). Beide sind deutsche GmbHs. DSGVO-mäßig kein Differenzierer. Aber wenn "100% deutsches Unternehmen, deutsche Daten, deutscher Support" für dich zählt, beide haben den Stempel.

**Reifes Produkt.** Pirsch läuft seit 2021, zahlende Kunden, durch DSGVO-Iterationen gegangen. Wir sind jünger.

## Wo wir gewinnen

**Free ohne Karte.** Pirsch ist nur Trial (30 Tage, dann zahlend). Wir sind 100k Hits/Mo free für immer, unbegrenzte Sites, alle 23 MCP-Tools. Für neue Projekte, bei denen du nicht weißt, ob sie laufen werden, zählt diese kostenlose Runway.

**100x Volumen-Headroom bei €19.** Bei ~$19/Mo-Äquivalent kriegst du 10.000.000 Hits bei uns und ~100k Pageviews bei Pirsch Plus. Andere Größenordnungen. Wenn du irgendeine Chance auf einen Hacker-News-Spike, Newsletter-Versand oder viralen Tweet hast, hittest du Pirschs Cap an einem einzigen Tag.

**MCP-natives Interface.** Der Grund warum es uns gibt. Deine Stats leben in deiner existierenden Claude/ChatGPT/Cursor-Session.

```
Du: "Pageviews letzte Woche vs Vorwoche. Was ist der größte
     Veränderer?"
Claude: "Pageviews 42.180 vs 31.420, plus 34%. Großer Sprung auf
        /pricing (8.2k vs 3.1k). Top neuer Referrer ist Reddit,
        Thread auf /r/selfhosted von Freitag."
```

**Bot-Crawler-Sicht.** Pirsch trackt AI-Referrer (Mensch-aus-AI). Wir klassifizieren zusätzlich AI-Crawler selbst (GPTBot, ClaudeBot, PerplexityBot, ByteSpider, etc.). Du siehst, wie oft deine Site von AI-Trainings-/Antwort-Systemen indiziert wird. Pirsch filtert die still raus.

**Server-Side-Events.** Unser Ingest-Endpoint nimmt `POST /event` direkt für Webhook-/Cron-/Server-Side-Conversion-Tracking entgegen. Erst-Party Ruby-Gem und npm-Wrapper sind auf der Pro-Roadmap. Pirsch ist JS-only.

**Wirklich unbegrenzte Sites auf allen Tiers**, inklusive Free. Pirsch cappt Standard bei 50 Sites. Großzügig, aber ein Cap.

## Wann du Pirsch nehmen solltest

- Dein Traffic ist klein und stabil (<10k/Mo) und du würdest lieber $6 zahlen als dir um Free-Tier-Limits Sorgen machen.
- Du willst ein sauberes Dashboard und der eingebaute AI-Referrer-Channel spricht deinen Use-Case an.
- Du nutzt Claude/ChatGPT/Cursor nicht als täglichen Workflow.

## Wann du uns nehmen solltest

- Du verbringst täglich Stunden in Claude oder ChatGPT.
- Free-Runway zählt. Keine Karte, keine Zeitfrist.
- Du könntest spiken. 100x mehr Hits beim selben Preis wie Pirsch Plus.
- Du willst explizite AI-Crawler-Sicht, kein stilles Filtern.
- Du brauchst Server-Side-Event-Tracking.

## Was kein echter Unterschied ist

- Beide EU-gehostet, beide deutsche Firmen.
- Beide cookielos im Strict-Modus per Default.
- Beide auf Privacy-first ausgerichtet.

## Migration

Lass beide einen Monat parallel laufen. Unser Snippet kollidiert nicht mit Pirschs. Häufiges Muster: Pirsch bleibt auf der Marketing-Site (Dashboard ist nützlich für nicht-technische Mit-Editoren), wir kommen auf interne Tools und Side-Projects (wo Chat-Workflow schneller ist).

## Loslegen

[Free anmelden](/), 100k Hits/Mo, keine Karte.

Spezifisches Pirsch-Feature, das du brauchst? [Email uns](mailto:hello@mcp-analytics.com).
