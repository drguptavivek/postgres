#!/usr/bin/env bash
set -euo pipefail

: "${APP_USER:?APP_USER is required}"
: "${APP_DB:?APP_DB is required}"
: "${APP_SCHEMA:?APP_SCHEMA is required}"
: "${PGPASSWORD_FILE:?PGPASSWORD_FILE is required}"

PGHOST="${PGHOST:-pgdb}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${POSTGRES_DB:-postgres}"

if [ "$APP_SCHEMA" = "public" ]; then
  echo "WARN: APP_SCHEMA=public. You'll operate in the public schema; consider using a dedicated schema for stricter isolation." >&2
fi

export PGPASSWORD="$(tr -d '\r\n' < "$PGPASSWORD_FILE")"
APP_PASS="$(tr -d '\r\n' < /run/secrets/APP_PASSWORD)"

# run psql (no exec, so we can do follow-up steps)
psql -v ON_ERROR_STOP=1 \
     -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
     -v APP_USER="$APP_USER" \
     -v APP_DB="$APP_DB" \
     -v APP_SCHEMA="$APP_SCHEMA" \
     -v APP_PASSWORD="$APP_PASS" \
     -f /sql/create_app.sql

# optional wait (useful if you chain follow-up tools)
sleep 2

# ---- Print connection string (masked) ----
# Build a masked DSN for copy/paste without leaking the password
MASKED_PASS="$(printf '%s' "$APP_PASS" | sed 's/./*/g')"
DSN_MASKED="postgres://${APP_USER}:${MASKED_PASS}@${PGHOST}:${PGPORT}/${APP_DB}?search_path=${APP_SCHEMA}"

echo
echo "------------------------------------"
echo " Postgres connection (masked):"
echo " ${DSN_MASKED}"
echo
echo " psql (masked) example:"
echo " PGPASSWORD=***** psql -h ${PGHOST} -p ${PGPORT} -U ${APP_USER} -d ${APP_DB} -v ON_ERROR_STOP=1 -c 'SHOW search_path;'"
echo "------------------------------------"



if [ "$APP_SCHEMA" = "public" ]; then
  echo "WARN: APP_SCHEMA=public. Rights on the public schema are restricted; consider using a dedicated schema for stricter isolation." >&2
fi
