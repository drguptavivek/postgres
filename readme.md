Perfect — here are **three separate Compose files** plus the tiny support files you’ll need. They work together like this:

* **01 – Initial cluster**: brings up Postgres + Adminer + pgAdmin, turns on sane defaults (SCRAM, logging), enables replication, creates a **replication user**, and opens `pg_hba.conf` for your Docker network. Bind mounts configs for Postgres. 
* **02 – App-specific DBs**: a one-shot “dbtool” job that creates **per-app database + role + schema grants** against the running cluster (idempotent).
* **03 – Backups (pg_basebackup)**: a sidecar that **runs `pg_basebackup` on a schedule** to a local volume.

---

# 00) Secrets


in the secrtes folder
Also add 
- PGADMIN_DEFAULT_EMAIL

```
cd secrets
nano PGADMIN_DEFAULT_EMAIL
# Type the enail ID, save, exit
```

Generate the basic secrets
- POSTGRES_PASSWORD
- REPL_PASSWORD
- PGADMIN_DEFAULT_PASSWORD



```bash
# SCRIPT - idempotent - does not owerwrite existing secrets
./scripts/gen_secrets.sh 

# OR CMDLINE
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/POSTGRES_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/REPL_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/PGADMIN_DEFAULT_PASSWORD

```

---

# 01) `docker-compose.init.yml`

*(Postgres + Adminer + pgAdmin, hardening, replication-ready)*

bind-mounts editable Postgres config files from your host. We point Postgres to those files explicitly, so you can tweak them without rebuilding the container.


```yaml
services:
  pgdb:
    image: postgres:17.3
    container_name: pgdb
    restart: always
    shm_size: 128mb
    ports:
      - "127.0.0.1:5432:5432"     # local-only exposure
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
      POSTGRES_PASSWORD_FILE: /run/secrets/POSTGRES_PASSWORD
      # Do NOT put POSTGRES_PASSWORD in .env when using secrets
    secrets:
      - POSTGRES_PASSWORD
      - REPL_PASSWORD
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER:-postgres}\" -d \"$${POSTGRES_DB:-postgres}\""]
      interval: 5s
      timeout: 5s
      retries: 20
    networks:
      - pgnet

  adminer:
    image: adminer
    container_name: adminer
    restart: always
    ports:
      - "127.0.0.1:8080:8080"
    depends_on:
      pgdb:
        condition: service_healthy
    networks:
      - pgnet

  pgadmin:
    image: dpage/pgadmin4
    container_name: pgadmin
    restart: always
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_DEFAULT_EMAIL:-admin@example.com}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_DEFAULT_PASSWORD:-change-me}
    ports:
      - "127.0.0.1:16543:80"
    depends_on:
      pgdb:
        condition: service_healthy
    networks:
      - pgnet

volumes:
  pgdata:

networks:
  pgnet:
    driver: bridge
    name: pgnet

secrets:
  POSTGRES_PASSWORD:
    file: ./secrets/POSTGRES_PASSWORD
  REPL_PASSWORD:
    file: ./secrets/REPL_PASSWORD
```
 

### `scripts/02_create_rotate_replication_user.sh`


```bash
#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-pgdb}"
SECDIR="${SECDIR:-secrets}"

PG_PASS="$(tr -d '\n' < "${SECDIR}/POSTGRES_PASSWORD")"
REPL_PASS="$(tr -d '\n' < "${SECDIR}/REPL_PASSWORD")"

docker exec -i -e PGPASSWORD="$PG_PASS" "$CONTAINER" \
  psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" \
  -v REPL_PASSWORD="$REPL_PASS" <<'SQL'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
    EXECUTE format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'REPL_PASSWORD');
  ELSE
    -- rotate to match your file (idempotent if same)
    EXECUTE format('ALTER ROLE replicator WITH PASSWORD %L', :'REPL_PASSWORD');
  END IF;
END
$do$;
SQL
echo "✓ replicator ensured/rotated"

```

> **Setup**:
>
> ```bash
> # Ensure secrets exist (from your earlier generator)
> sudo chmod +x ./scripts/gen_secrets.sh 
> ./scripts/gen_secrets.sh 
> 
> # Start / restart POSTGRES and PGAMDIN AND ADMINER containers
> docker compose -f docker-compose.init.yml up -d
> 
> # REPLICATION USER
> chmod +x scripts/create_or_rotate_replicator.sh
> scripts/create_or_rotate_replicator.sh
> 
> # After editing config files:
> docker restart pgdb
> # Or reload when supported:
> docker exec -it pgdb psql -U postgres -c "SELECT pg_reload_conf();"
> ```

---


### Notes & gotchas
- First init vs existing data: If you already initialized PGDATA with different settings, Postgres will still honor the config_file we pass in command:. That’s why we explicitly set config_file — it works both on a fresh and an existing data directory.
- Permissions: Files are mounted :ro; Postgres only needs read access. Keep them owned by you on the host.
- Network CIDR: Adjust the 172.18.0.0/16 in pg_hba.conf to match docker network inspect pgnet.
- Conf.d strategy: put most of your tunables in conf.d/*.conf. Keep postgresql.conf short and stable (paths + includes).
- If you want, say your host’s RAM/CPU and I’ll give you a tuned conf.d/10-tuning.conf for that machine.



# 02) `docker-compose.apps.yml`

*(One-shot job to create per-app DBs/roles; safe to re-run)*

```yaml
version: "3.9"

services:
  dbtool:
    image: postgres:17.3
    container_name: dbtool
    restart: "no"
    depends_on:
      pgdb:
        condition: service_healthy
    environment:
      PGHOST: pgdb
      PGPORT: 5432
      PGUSER: ${POSTGRES_USER:-postgres}
      PGPASSWORD_FILE: /run/secrets/POSTGRES_PASSWORD
    entrypoint: ["/bin/bash", "-lc"]
    command: >
      '
      export PGPASSWORD="$(cat $PGPASSWORD_FILE)";
      # Create App A
      psql -v ON_ERROR_STOP=1 -d postgres \
        -v APP_USER=appA_user -v APP_DB=appA_db -v APP_SCHEMA=appA \
        -v APP_PASSWORD="$(cat /run/secrets/APP_A_PASSWORD)" \
        -f /sql/create_app.sql;
      # Create App B (example second app)
      psql -v ON_ERROR_STOP=1 -d postgres \
        -v APP_USER=appB_user -v APP_DB=appB_db -v APP_SCHEMA=appB \
        -v APP_PASSWORD="$(cat /run/secrets/APP_B_PASSWORD)" \
        -f /sql/create_app.sql;
      '
    volumes:
      - ./apps/create_app.sql:/sql/create_app.sql:ro
    secrets:
      - POSTGRES_PASSWORD
      - APP_A_PASSWORD
      - APP_B_PASSWORD
    networks:
      - pgnet

networks:
  pgnet:
    external: false
    name: pgnet   # same network name as in the init compose

secrets:
  POSTGRES_PASSWORD:
    file: ./secrets/POSTGRES_PASSWORD
  APP_A_PASSWORD:
    file: ./secrets/APP_A_PASSWORD
  APP_B_PASSWORD:
    file: ./secrets/APP_B_PASSWORD
```

### `apps/create_app.sql` (template used twice above)

```sql
-- Variables provided by psql -v: APP_USER, APP_DB, APP_SCHEMA, APP_PASSWORD

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'APP_USER') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'APP_USER', :'APP_PASSWORD');
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'APP_DB') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'APP_DB', current_user);
  END IF;
END$$;

\connect :APP_DB

-- Dedicated schema
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = :'APP_SCHEMA') THEN
    EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I', :'APP_SCHEMA', current_user);
  END IF;
END$$;

-- Connect & usage
EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', :'APP_DB', :'APP_USER');
EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', :'APP_SCHEMA', :'APP_USER');

-- Default privileges for future objects created by DB owner in this schema
ALTER DEFAULT PRIVILEGES IN SCHEMA :APP_SCHEMA GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA :APP_SCHEMA GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :APP_USER;

-- Existing objects, if any
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA :APP_SCHEMA TO :APP_USER;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA :APP_SCHEMA TO :APP_USER;
```

> **Usage**:
>
> ```bash
> # Prepare secrets for each app user:
> # add app name to /scripts/gen_secrets.sh   adfter line 25 
> # gen APP_XXX_PASSWORD
> # generate secret by  running the app
> ./scripts/gen_secrets.sh   
>
> # Run the one-shot job:
> docker compose -f docker-compose.apps.yml run --rm dbtool
> ```

### Your app connects with
> `postgresql://appA_user:super-secret-A@pgdb:5432/appA_db?search_path=appA`

---

# 03) `docker-compose.backup.yml`

*(Scheduled **pg_basebackup** to a local volume; uses `replicator` user)*

```yaml
version: "3.9"

services:
  pg_basebackup_runner:
    image: postgres:17.3
    container_name: pg_basebackup_runner
    restart: always
    depends_on:
      pgdb:
        condition: service_healthy
    environment:
      PGHOST: pgdb
      PGPORT: 5432
      PGUSER: replicator
      PGPASSWORD_FILE: /run/secrets/REPL_PASSWORD
      BACKUP_DIR: /backups/full
      SCHEDULE_CRON: "0 3 * * *"   # daily at 03:00
    secrets:
      - REPL_PASSWORD
    volumes:
      - ./backups:/backups
    networks:
      - pgnet
    entrypoint: ["/bin/bash", "-lc"]
    command: >
      '
      export PGPASSWORD="$(cat $PGPASSWORD_FILE)";
      echo "${SCHEDULE_CRON} pg_basebackup -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} \
        -D ${BACKUP_DIR}/$(date +\%F_\%H-\%M-\%S) \
        -X stream -R -F tar -z --progress --write-recovery-conf \
        || echo \"pg_basebackup failed on $(date)\" 1>&2" | crontab - ;
      crond -f -L /dev/stdout
      '
networks:
  pgnet:
    external: false
    name: pgnet

secrets:
  REPL_PASSWORD:
    file: ./secrets/REPL_PASSWORD
```

### What this backup gives you

* A **compressed tar** base backup each night under `./backups/full/YYYY-MM-DD_HH-MM-SS/`.
* `-X stream` includes the WAL needed to make the backup consistent.
* `-R --write-recovery-conf` writes the files needed for recovery if you restore as a standby.

### Restore (example)

```bash
# Stop Postgres and move aside old data dir
docker stop pgdb
mv ./pgdata ./pgdata.bak.$(date +%s)

# Extract a chosen base backup into a fresh data dir
mkdir -p ./pgdata
tar -xzf ./backups/full/2025-10-29_03-00-00/base.tar.gz -C ./pgdata

# Ensure ownership (host varies; in container it's postgres:postgres)
sudo chown -R 999:999 ./pgdata   # 999 is the postgres UID in the image

# Start the DB; it will use recovery settings created by -R
docker start pgdb
```

> If you want **per-database logical dumps** too (easy restore & portability), you can additionally run a `pg_dump` sidecar; but you asked specifically for **pg_basebackup**, so the above gives you **physical full backups**.

---

## Notes & knobs you can tweak

* **Docker subnet in `01_append_pg_hba.sh`**: Confirm your bridge network CIDR (e.g. `docker network inspect pgnet`). Update `DOCKER_SUBNET` if needed.
* **Security**: All passwords come from `./secrets/*` files (chmod 600). Never commit them.
* **Retention**: The `pg_basebackup_runner` above doesn’t prune old backups; prune with a host cron or add a small cleanup step after the backup runs (tell me your retention policy and I’ll wire it in).
* **RPO**: `pg_basebackup` once nightly means you can lose up to a day’s data. If you need tighter RPO, add **WAL archiving** (e.g., WAL-G to S3/MinIO) alongside or increase frequency.

---

You don’t need hard-coded `echo` lines—generate strong random secrets safely and idempotently.

# Quick one-liners (Linux/macOS)

```bash
# Creates ./secrets if missing, sets 600 perms, and generates strong, newline-free secrets

./scripts/gen_secrets.sh  


# Superuser + replication (for compose.init.yml)
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/POSTGRES_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/REPL_PASSWORD

# App users (for compose.apps.yml)
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/APP_A_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/APP_B_PASSWORD
```

* `umask 177` ⇒ files created with `0600`.
* `-base64 48` ⇒ ~64 chars; high entropy.
* `tr -d '\n'` strips newline so the password is a single line.

