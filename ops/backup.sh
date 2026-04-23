#!/usr/bin/env bash
# Nightly backup script for the mcp-analytics server.
# Install on the host (NOT in a container) via cron:
#   17 3 * * * /srv/mcp-analytics/ops/backup.sh >> /var/log/mcp-backup.log 2>&1
#
# What it does:
#   1. Snapshots the Rails SQLite databases with `sqlite3 .backup` (safe under WAL).
#   2. Runs a ClickHouse BACKUP to a local directory.
#   3. Optionally mirrors to an offsite bucket if S3_DEST is set.
#
# Retention: keeps 7 local daily snapshots.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mcp-analytics}"
STAMP="$(date -u +%Y-%m-%d)"
DEST="${BACKUP_DIR}/${STAMP}"
mkdir -p "${DEST}"

echo "[backup] ${STAMP} → ${DEST}"

# --- Rails SQLite snapshots -------------------------------------------------

for db in production production_cache production_queue production_cable; do
  SRC="/var/lib/docker/volumes/mcp-analytics_mcp_storage/_data/${db}.sqlite3"
  if [[ -f "${SRC}" ]]; then
    docker run --rm -v mcp-analytics_mcp_storage:/data -v "${DEST}":/out \
      alpine:3.20 sh -c "apk add --no-cache sqlite >/dev/null && \
        sqlite3 /data/${db}.sqlite3 \".backup '/out/${db}.sqlite3'\""
    gzip -f "${DEST}/${db}.sqlite3"
  fi
done

# --- ClickHouse -------------------------------------------------------------

docker exec mcp-analytics-clickhouse clickhouse-client --query \
  "BACKUP DATABASE mcpa TO File('/var/lib/clickhouse/backup/${STAMP}')" \
  || echo "[backup] clickhouse backup failed (non-fatal)"

docker cp "mcp-analytics-clickhouse:/var/lib/clickhouse/backup/${STAMP}" \
  "${DEST}/clickhouse" \
  || echo "[backup] clickhouse copy failed"

# --- Offsite mirror (optional) ----------------------------------------------

if [[ -n "${S3_DEST:-}" ]]; then
  aws s3 sync "${DEST}" "${S3_DEST}/${STAMP}/" --delete
fi

# --- Retention --------------------------------------------------------------

find "${BACKUP_DIR}" -maxdepth 1 -type d -name '20*' -mtime +7 -print -exec rm -rf {} +

echo "[backup] done"
