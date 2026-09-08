#!/usr/bin/env bash
# Exporter loop: on boot (and then every REFRESH_INTERVAL_SECONDS) run the ADO
# DORA exporters, then load their CSVs into Postgres. A plain sleep loop is used
# instead of cron so the slim image needs no cron daemon and logs go straight to
# `docker compose logs`.
set -euo pipefail

: "${DORA_ORG:?set DORA_ORG in .env}"
: "${DORA_PROJECT:?set DORA_PROJECT in .env}"
: "${AZURE_DEVOPS_EXT_PAT:?set AZURE_DEVOPS_EXT_PAT (ADO PAT) in .env}"

SINCE="${DORA_SINCE:-$(python3 -c 'import datetime as d; y=d.date.today().year-1; print(f"{y}-10-01")')}"
TARGET_BRANCH="${DORA_TARGET_BRANCH:-main}"
PROD_ENV="${DORA_PROD_ENV:-prod}"
INTERVAL="${REFRESH_INTERVAL_SECONDS:-3600}"
OUT_DIR="/tmp/dora-out"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }

wait_for_db() {
  log "waiting for postgres at ${PGHOST}:${PGPORT} ..."
  for _ in $(seq 1 60); do
    if python3 -c "import psycopg,os; psycopg.connect().close()" 2>/dev/null; then
      log "postgres is up"
      return 0
    fi
    sleep 2
  done
  log "ERROR: postgres never became reachable"
  return 1
}

run_once() {
  mkdir -p "$OUT_DIR"
  log "running ado-dora (org=${DORA_ORG} project=${DORA_PROJECT} since=${SINCE})"
  local extra=()
  if [ -n "${DORA_RELIABILITY_AREA_PATH:-}" ]; then
    extra+=(--reliability-area-path "${DORA_RELIABILITY_AREA_PATH}")
  fi
  ado-dora \
    --organization "$DORA_ORG" \
    --project "$DORA_PROJECT" \
    --since "$SINCE" \
    --target-branch "$TARGET_BRANCH" \
    --prod-env "$PROD_ENV" \
    --output-dir "$OUT_DIR" \
    "${extra[@]}"

  log "loading CSVs into postgres"
  dora-load \
    --organization "$DORA_ORG" \
    --project "$DORA_PROJECT" \
    --since "$SINCE" \
    --input-dir "$OUT_DIR"
  log "load complete"
}

wait_for_db

while true; do
  if run_once; then
    log "sleeping ${INTERVAL}s until next refresh"
  else
    log "refresh FAILED; retrying in ${INTERVAL}s"
  fi
  sleep "$INTERVAL"
done
