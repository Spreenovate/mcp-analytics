# Deployment Checklist — Hetzner via Kamal 2

Schritt-für-Schritt zum ersten Live-Deploy. Alles unter ~2 h, wenn
Domain + Server schon bestellt sind.

---

## 0. Voraussetzungen besorgen (extern, kein Code)

- [ ] **Domain**: `mcp-analytics.com` (oder Wunschdomain)
      bei Registrar deiner Wahl (Namecheap, Cloudflare, etc.)
- [ ] **Hetzner Cloud Account** + neue **CX32** in Falkenstein bestellen:
  - 4 vCPU, 8 GB RAM, 80 GB SSD
  - Image: **Ubuntu 24.04 LTS**
  - SSH-Key beim Erstellen hinterlegen (deinen lokalen `~/.ssh/id_ed25519.pub`)
- [ ] **Mailgun-Account** (oder Postmark/SES) für SMTP
  - Domain `mcp-analytics.com` verifizieren (DKIM/SPF Records bei deinem
    Registrar setzen)
  - SMTP-Credentials notieren
- [ ] **GitHub Container Registry** Zugang
  - Personal Access Token mit `write:packages` Scope erstellen
  - Token notieren

---

## 1. DNS-Records setzen

Beim Registrar / DNS-Provider zwei A-Records anlegen:

```
mcp-analytics.com     A  <hetzner-ipv4>
t.mcp-analytics.com   A  <hetzner-ipv4>
```

Optional:
```
www.mcp-analytics.com  CNAME  mcp-analytics.com.
```

**Warten** bis `dig mcp-analytics.com` die richtige IP liefert (meist
< 5 min, manchmal 1–2 h).

---

## 2. `config/deploy.yml` anpassen

In drei Stellen die Platzhalter-IP `1.2.3.4` durch die echte Hetzner-IP
ersetzen:

```yaml
servers:
  web:
    hosts:
      - <hetzner-ipv4>
  ingest:
    hosts:
      - <hetzner-ipv4>

accessories:
  clickhouse:
    host: <hetzner-ipv4>
```

Wenn Domain nicht `mcp-analytics.com` ist, auch anpassen:
- `proxy.host` für `web` und `ingest`
- `env.clear.PUBLIC_BASE_URL`, `PUBLIC_HOST`, `TRACKER_BASE_URL`,
  `ADDITIONAL_HOSTS`
- `env.clear.MAIL_FROM`, `OPERATOR_EMAIL`

Das committen.

---

## 3. Server vorbereiten

SSH einmal manuell rein um Server-Fingerprint zu vertrauen:

```sh
ssh root@<hetzner-ipv4>
# yes
exit
```

Kamal installiert Docker + alles weitere selbstständig im nächsten Schritt.

**ClickHouse-Datenpfad** auf der Server-SSD anlegen (das Verzeichnis
muss existieren bevor der Container es mounted):

```sh
ssh root@<hetzner-ipv4> "mkdir -p /var/lib/clickhouse && chown -R 101:101 /var/lib/clickhouse"
```

(101:101 ist der `clickhouse` User im offiziellen Image.)

---

## 4. Secrets in Shell exportieren

Lokal — nicht committen, nicht in Files schreiben:

```sh
export KAMAL_REGISTRY_PASSWORD=<ghcr-pat>
export RAILS_MASTER_KEY=$(cat config/master.key)
export SMTP_USERNAME=<mailgun-smtp-user>
export SMTP_PASSWORD=<mailgun-smtp-pw>
export CLICKHOUSE_PASSWORD=$(openssl rand -hex 32)
```

Kamal liest die aus `.kamal/secrets`, wo die Variablen-Namen referenziert
sind (siehe Datei).

**`CLICKHOUSE_PASSWORD` ist neu** — wird beim ersten Deploy in der
ClickHouse-Initialisierung gesetzt. Notiere ihn dir, du brauchst ihn
ggf. für Backup-Skripte.

---

## 5. Erstes Setup + Deploy

```sh
# Installiert Docker + kamal-proxy auf dem Server, lädt erste Images
kamal setup
```

Dauert beim ersten Mal 5–10 min (Docker installieren, Images bauen +
pushen, Container starten, Let's Encrypt Zertifikate holen).

Wenn alles grün:

```sh
# Health-Check
curl https://mcp-analytics.com/up    # → "OK"
curl https://t.mcp-analytics.com/healthz  # → 204
curl https://t.mcp-analytics.com/script.js  # → JS Code
curl -sX POST https://mcp-analytics.com/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
# → JSON mit "protocolVersion":"2025-06-18"
```

---

## 6. Backup-Cron einrichten

Auf dem Server:

```sh
ssh root@<hetzner-ipv4>
# Backup-Skript ist über Kamal nicht auf den Host gemounted —
# eine Kopie hinterlegen:
mkdir -p /srv/mcp-analytics/ops
# Skript-Inhalt aus ops/backup.sh per scp oder Editor übertragen
chmod +x /srv/mcp-analytics/ops/backup.sh

# Crontab editieren:
crontab -e
# einfügen:
17 3 * * * /srv/mcp-analytics/ops/backup.sh >> /var/log/mcp-backup.log 2>&1
```

**Test:** einmal manuell laufen lassen und prüfen dass Files in
`/var/backups/mcp-analytics/` landen.

---

## 7. Smoketest mit echtem MCP-Client

1. **Claude Desktop / claude.ai** öffnen
2. **Settings → Connectors → Add custom connector**
3. URL eintragen: `https://mcp-analytics.com/mcp`
4. Im Chat sagen: *„Erstell mir bitte einen Account mit der Email
   `dein@email.de` über mcp-analytics."*
5. Claude sollte `register_account` aufrufen und eine Bestätigung
   ausspielen
6. Mail im Postfach checken → Verify-Link klicken → Token kopieren
7. Connector-URL aktualisieren auf
   `https://mcp-analytics.com/mcp?token=mcpa_xxx`
8. Im Chat: *„Füg mir bitte eine Site `test.com` hinzu im strict-Mode."*
9. Claude ruft `add_site` auf, gibt site_id zurück
10. Test-HTML-Datei lokal mit dem Tracking-Snippet erstellen, im Browser
    öffnen, dann in Claude: *„Wie viele Pageviews hatte ich gerade?"*

Wenn Schritt 10 funktioniert: **MVP ist live.**

---

## 8. Monitoring (minimal)

**Uptime-Check** (UptimeRobot oder ähnlich, kostenlos):
- Monitor 1: `https://mcp-analytics.com/up` (5 min Intervall)
- Monitor 2: `https://t.mcp-analytics.com/healthz`

**Disk-Alert** auf dem Host: einfacher Cron der `df` prüft:

```sh
# crontab
0 * * * * [ $(df / | awk 'NR==2 {print $5}' | tr -d '%') -gt 80 ] && echo "Disk >80%" | mail -s "[mcp-analytics] disk alert" alex@mcp-analytics.com
```

---

## Troubleshooting

**`kamal setup` hängt bei „Building image"**:
- Lokales Docker hat manchmal QEMU-Probleme bei amd64-Cross-Build auf
  Apple Silicon. Falls ja: `kamal build push` von Linux/CI aus, dann
  `kamal deploy` lokal.

**Let's Encrypt-Cert kommt nicht**:
- DNS muss VOR dem Setup propagiert sein. Check mit `dig +short
  mcp-analytics.com`.
- Port 80 + 443 müssen am Hetzner-Firewall erreichbar sein (default ja).

**ClickHouse-Container restart-loopt**:
- Permission-Problem auf `/var/lib/clickhouse`:
  `chown -R 101:101 /var/lib/clickhouse`.
- Init-SQLs failen: `kamal accessory logs clickhouse` checken.

**Rails kann ClickHouse nicht erreichen**:
- Beide müssen im Docker-Netzwerk `kamal` sein. Check:
  `docker network inspect kamal` auf dem Host, beide Container müssen
  als Member auftauchen.
- DNS-Name in `CLICKHOUSE_URL` ist `mcp-analytics-clickhouse`
  (Service-Name wie in Kamal-Konvention).

**SMTP-Mails kommen nicht an**:
- Mailgun-Domain wirklich verifiziert? Check Mailgun-Dashboard.
- Aus dem Container testen:
  `kamal app exec --interactive --reuse "rails console"` →
  `MagicLinkMailer.with(...).sign_in.deliver_now`
