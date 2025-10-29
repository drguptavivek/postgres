#!/usr/bin/env bash
set -euo pipefail

# Read secrets
POSTGRES_PASSWORD_FILE="/run/secrets/POSTGRES_PASSWORD"
REPL_PASSWORD_FILE="/run/secrets/REPL_PASSWORD"

export PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")"
REPL_PASS="$(cat "$REPL_PASSWORD_FILE")"

# Create REPLICATION user if missing
psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';
  END IF;
END\$