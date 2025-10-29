#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD_FILE:?PGPASSWORD_FILE is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"
SCHEDULE_CRON="${SCHEDULE_CRON:-0 16 * * *}"

# ensure cron exists (image doesn't ship it)
if ! command -v cron >/dev/null 2>&1; then
  echo "[pgbackup] installing cron..."
  apt-get update -y && apt-get install -y --no-install-recommends cron && rm -rf /var/lib/apt/lists/*
fi
# find pg_basebackup bin dir for cron PATH
BIN_DIR="$(dirname "$(command -v pg_basebackup)")"
: "${BIN_DIR:?pg_basebackup not found in PATH}"

mkdir -p /etc/cron.d /var/log
touch /var/log/cron.log

# non-secret env for the job
cat > /etc/pgbackup_env <<ENV
PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGUSER=${PGUSER}
BACKUP_DIR=${BACKUP_DIR}
ENV

# cron entry (include BIN_DIR and your timezone)
cat > /etc/cron.d/pg_basebackup <<EOF
SHELL=/bin/bash
TZ=${TZ:-Asia/Kolkata}
PATH=${BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${SCHEDULE_CRON} root /usr/local/bin/pg_do_basebackup.sh >> /var/log/cron.log 2>&1
EOF
chmod 0644 /etc/cron.d/pg_basebackup



echo "[pgbackup] Scheduled '${SCHEDULE_CRON}' -> /usr/local/bin/pg_do_basebackup.sh"
echo "[pgbackup] Logs at /var/log/cron.log ; backups to ${BACKUP_DIR}"

if [[ "${RUN_ONCE:-false}" == "true" ]]; then
  echo "[pgbackup] RUN_ONCE=true -> running immediate backup and exiting"
  /usr/local/bin/pg_do_basebackup.sh
  exit $?
fi

exec cron -f
