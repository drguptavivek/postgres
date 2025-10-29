#!/usr/bin/env bash
set -euo pipefail

export PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
APP_PASS="$(cat /run/secrets/APP_PASSWORD)"

exec psql -v ON_ERROR_STOP=1 \
     -d "${POSTGRES_DB:-postgres}" \
     -U "${POSTGRES_USER:-postgres}" \
     -v APP_USER="fundusAppUser" \
     -v APP_DB="fundusAppDb" \
     -v APP_SCHEMA="fundusAppSchema" \
     -v APP_PASSWORD="$APP_PASS" \
     -f /sql/create_app.sql
