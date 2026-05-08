#!/bin/sh
# Ingest container entrypoint.
#
# Background side-job: re-run the Phase-2 traffic classifier over the
# historic `events` table once on startup, then every 24h. Idempotent
# — when nothing needs updating it's a sub-second SELECT against
# ClickHouse, costs essentially nothing.
#
# Why a shell loop and not cron: busybox crond doesn't pass the
# container's environment through to its children, so `CLICKHOUSE_URL`
# etc. would have to be either rewritten into /etc/crontabs/<user> at
# runtime or duplicated at the top of the crontab. A shell loop
# inherits the container env directly via the process tree, and the
# only operational need (on-boot + daily) is trivially expressed.
#
# `set -e` is intentionally NOT set: a single failed reclassify run
# (network blip, ClickHouse restart, etc.) must not kill the loop or
# bring down the ingest server. `|| true` after the call absorbs any
# non-zero exit. `timeout 300` caps a stuck run so a hung HTTP request
# can't keep the loop wedged forever.

(
  # Sanity-check the binary on first launch. Without this a botched
  # build / missing COPY would silently 127 → `|| true` → 24h of
  # nothing happening. Log loudly so a missing binary surfaces in
  # `kamal app logs` immediately.
  if [ ! -x /app/reclassify ]; then
    echo "[reclassify] FATAL /app/reclassify missing or not executable; loop disabled" >&2
    exit 0
  fi

  # `pipefail` so `$?` after the `timeout … | sed` pipe reflects
  # timeout's exit (not sed's, which is always 0). Without this the
  # whole crash-visibility logic below silently degrades.
  set -o pipefail

  # Wait briefly so ingest's own boot logs settle first; keeps
  # `kamal app logs` readable on first start.
  sleep 30
  while true; do
    # `-k 30 300`: SIGTERM after 5 min, SIGKILL 30 s later. Without
    # -k busybox `timeout` only sends SIGTERM and lets the process
    # linger if it ignores the signal — would wedge the loop
    # indefinitely. Output piped through sed for a stable
    # `[reclassify]` log prefix so it doesn't blend into ingest's
    # own log lines. `sed -u` keeps the stream unbuffered. Exit
    # code logged explicitly when non-zero so a crash before the
    # first slog line (OOM kill, missing-binary regression, CH
    # unreachable) is visible instead of vanishing.
    timeout -k 30 300 /app/reclassify --apply 2>&1 \
      | sed -u 's/^/[reclassify] /'
    rc=$?
    [ "$rc" -eq 0 ] || echo "[reclassify] run exited rc=$rc"
    sleep 86400
  done
) &

# Hand control to ingest as PID 1's main role. When ingest exits the
# container exits, and the OS kills the background loop along with it.
exec /app/ingest "$@"
