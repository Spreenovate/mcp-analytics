---
competitor: "Fathom Analytics"
competitor_url: "https://usefathom.com"
slug: fathom
title: "mcp-analytics vs Fathom Analytics (2026)"
description: "Fathom ist die Premium-UX im Privacy-first Analytics. Wir sind MCP-nativ. Wo welches gewinnt, wo keins passt."
date: 2026-05-19
hreflang_alt: fathom
verdict_us: "Für den Claude/Cursor-Power-User, der Stats im Chat will. Free 100k Hits/Mo ohne Karte. Bot-/AI-Crawler-Taxonomie. EU-gehostet."
verdict_them: "Für den ästhetik-bewussten Founder, der ein schönes Single-Pane-Dashboard will. Reifes Produkt, unbegrenzte Sites auf allen Plänen, EU-isoliertes Hosting optional."
table:
  - feature: "Preis-Einstieg"
    us: "Free 100k Hits/Mo, keine Karte.\n€19/Mo für 10M Hits."
    them: "30-Tage-Trial, kein Free.\n$15/Mo für 100k Pageviews."
  - feature: "Hits bei $15-€19"
    us: "10.000.000 / Monat"
    them: "100.000 / Monat"
  - feature: "Dashboard UI"
    us: "Keine. MCP-only."
    them: "Polished, single-page, fürs Teilen designt."
  - feature: "MCP-Server"
    us: "Ja, primäres Interface. 23 Tools."
    them: "Nein."
  - feature: "Unbegrenzte Sites"
    us: "Ja, alle Tiers."
    them: "Ja, alle Tiers."
  - feature: "EU-isoliertes Hosting"
    us: "Hetzner Falkenstein (Deutschland), immer."
    them: "EU-isolierte Option; Default ist Shared US/EU."
  - feature: "Cookielos"
    us: "Ja im Strict-Modus."
    them: "Ja per Default."
  - feature: "Custom Events"
    us: "JS + Server-Side-SDK auf Pro."
    them: "JS-only auf Cloud."
  - feature: "AI- / Bot-Taxonomie"
    us: "8 Traffic-Klassen inkl. ai_user_action und ai_crawler."
    them: "Bots werden still gefiltert."
  - feature: "Datenhaltung"
    us: "1 Jahr (Free) / 3 Jahre (Pro) / Custom (Enterprise)."
    them: "Unbegrenzt auf bezahlten Plänen."
  - feature: "Public Dashboards"
    us: "Nein (nur privat)."
    them: "Ja, One-Click Public-Sharing."
---

Fathom ist der Premium-Ästhetik-Player im Privacy-first-Analytics-Markt. Ihr Dashboard ist genuin schön, ihre Marke ist stark, sie laufen seit 2018 mit einem Single-Page-Design, das bis heute hält.

mcp-analytics ist eine andere Wette. Beide sind privacy-first; beide hosten in der EU; beide sind Subscription-Produkte. Der Unterschied ist das Interface. Die ehrliche Variante:

## Wo Fathom gewinnt

**Das Dashboard.** Fathoms Single-Pane ist wohl das schönste Analytics-Dashboard überhaupt. Wenn du in 5 Sekunden auf deine Stats schauen willst und es soll sich angenehm anfühlen, gewinnt Fathom. Wir haben gar kein Dashboard. Das ist das ganze Produkt, aber es heißt, wir werden Fathom auf dieser Achse nie schlagen.

**Reifes Produkt.** Fathom läuft seit 2018, hat Tausende zahlende Kunden, ist durch jeden Privacy-Shift gegangen. Wir sind jünger.

**Public Dashboards.** Fathom lässt dich eine öffentliche, read-only Version deines Dashboards mit einem Klick teilen. Wir haben kein Pendant (kein Dashboard zum Teilen). Wenn Transparenz Use-Case ist (ein offenes Side-Project, Benchmarking), ist Fathom das richtige Tool.

**Forever-Retention auf bezahlten Plänen.** Fathom behält deine Daten für immer auf jedem zahlenden Tier. Wir 1 Jahr (Free), 3 Jahre (Pro), Custom (Enterprise). Wenn Langzeit-Aufbewahrung kritisch ist, ist Fathom großzügiger.

**EU-isoliertes Hosting (opt-in).** Fathom bietet EU-isoliertes Hosting an; Default ist Shared US/EU. Falls Compliance ein ernsthaftes Anforderung ist, wert zu wissen.

## Wo wir gewinnen

**Free-Tier.** Fathom hat kein Free. 30-Tage-Trial, dann mindestens $15/Mo. Wir haben 100.000 Hits/Mo free für immer, unbegrenzte Sites, alle Features. Der Unterschied zwischen "einmal probiert" und "zwei Jahre später noch dabei" liegt an diesem Gate.

**100x mehr Volumen beim gleichen Preis.** $15-19/Mo gibt dir 100k Pageviews bei Fathom und 10M Hits bei uns. Wenn du einen viel-gelesenen Newsletter, Blog oder irgendwas hast, das gelegentlich spikt, bedeutet dieser Faktor 100, dass du dir keine Overage-Sorgen machst.

**MCP-Primärinterface.** Das ist der Grund, warum es uns gibt. Web-Analytics, das komplett in deiner Claude- / ChatGPT- / Cursor-Session lebt. Du fragst in normalem Deutsch, der LLM wählt das passende Tool, du bekommst eine Antwort.

```
Du: "Letzte 7 Tage vs die 7 Tage davor für die Launch-Landing."
Claude: "Pageviews 12.840 (plus 47%), aber Bounce-Rate von 38% auf
        61% gesprungen. Top neuer Referrer ist Hacker News, vermutlich
        ein einzelner Thread, der viel Low-Intent-Traffic schickt. Dein
        Conversion-Event 'signup_started' flat bei 287 vs 281."
```

Fathom hat eine API, aber kein Chat-Interface. Ihr Dashboard verlangt einen Tab und Klicks.

**AI-Crawler-Sicht.** Wir klassifizieren Traffic in acht Buckets inklusive `ai_user_action` (Claude oder ChatGPT holt eine Page für einen User), `ai_crawler` (GPTBot, ClaudeBot, etc.) und `verified_search_bot` (Googlebot et al). Fathom filtert Bots still. Du siehst deinen GPTBot-Anteil nicht.

**Server-Side-Events vom Backend.** Unser Ingest-Endpoint nimmt `POST /event` direkt entgegen. Du kannst Webhook-Deliveries, Server-Side-Conversions, Cron-Jobs tracken. Alles, was der JS-Tracker nie sieht. Erst-Party Ruby-Gem und npm-Wrapper sind auf der Pro-Roadmap. Fathom ist JS-only auf Cloud (die selbst-gehostete Lite-Version ist anders).

## Wann du Fathom nehmen solltest

- Du legst Wert aufs Dashboard und das Public-Sharing-Feature.
- Du hast stabilen, niedrigvolumigen Traffic (deutlich unter 100k/Mo).
- Du willst ein reifes, bekanntes Produkt mit Tausenden Kunden als Risiko-Buffer.
- Langzeit-Aufbewahrung ist nicht verhandelbar.

## Wann du uns nehmen solltest

- Du verbringst täglich Stunden in Claude/ChatGPT/Cursor.
- Du willst echtes Free, das du ohne Karte langfristig nutzen kannst.
- Dein Traffic könnte spiken. 100x mehr Headroom bei vergleichbarem Preis.
- Du willst explizite AI-Crawler-Aufschlüsselung.
- Du brauchst Server-Side-Events.

## Was kein echter Unterschied ist

- Beide EU-gehostet (wir immer; Fathom auf EU-isoliertem Tier).
- Beide cookielos im Strict-Modus.
- Beide unbegrenzte Sites auf allen Tiers.
- Beide zielen auf den Privacy-first-Markt.

## Migration

Du kannst beide parallel laufen lassen. Fathom-Snippet und unser Snippet kollidieren nicht. Add uns daneben, stell dieselben Fragen in beiden für einen Monat, dann entscheide.

Viele Teams behalten Fathom auf der Marketing-Hauptsite (fürs Dashboard) und nehmen uns auf Side-Projects und interne Tools (für den Chat-Workflow). Keine Regel sagt, dass eins gewinnen muss.

## Loslegen

[Free anmelden](/), 100k Hits/Mo, keine Karte.

Spezifisches Fathom-Feature, von dem du Angst hast es zu verlieren? [Email uns](mailto:hello@mcp-analytics.com).
