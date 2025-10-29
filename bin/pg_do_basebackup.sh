#!/usr/bin/env bash
set -euo pipefail

# Load non-secret env
[[ -f /etc/pgbackup_env ]] && source /etc/pgbackup_env

# Read secret fresh each run (so rotation is picked up)
PGPASSWORD="$(tr -d '\r\n' < /run/secrets/REPL_PASSWORD)"
export PGPASSWORD

ts="$(date +%F_%H-%M-%S)"
dest="${BACKUP_DIR}/${ts}"
mkdir -p "$dest"

echo "[pgbackup] $(date -Is) starting basebackup to ${dest}"

pg_basebackup \
  -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
  -D "$dest" \
  -X stream -R -F tar -z --progress \
|| { echo "[pgbackup] $(date -Is) basebackup FAILED"; exit 1; }

echo "[pgbackup] $(date -Is) basebackup DONE -> ${dest}"
