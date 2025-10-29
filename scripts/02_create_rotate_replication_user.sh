#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-pgdb}"
SECDIR="${SECDIR:-secrets}"   # change to ".secrets" if that's your folder

# read secrets on the HOST, not from inside the container
PG_PASS="$(tr -d '\r\n' < "${SECDIR}/POSTGRES_PASSWORD")"
REPL_PASS="$(tr -d '\r\n' < "${SECDIR}/REPL_PASSWORD")"

# connect into the container; use client-side env for psql auth
docker exec -i \
  -e PGPASSWORD="$PG_PASS" \
  "$CONTAINER" \
  psql --no-psqlrc -v ON_ERROR_STOP=1 \
       -U "${POSTGRES_USER:-postgres}" \
       -d "${POSTGRES_DB:-postgres}" <<SQL
DO \$do\$
DECLARE
  pw text := \$q\$${REPL_PASS}\$q\$;  -- safe, no -v substitution problems
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
    EXECUTE 'CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD ' || quote_literal(pw);
  ELSE
    EXECUTE 'ALTER ROLE replicator WITH PASSWORD ' || quote_literal(pw);
  END IF;
END
\$do\$;
SQL

echo "✓ replication role 'replicator' ensured/rotated"
