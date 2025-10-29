

#  `docker-compose.apps.yml`

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
        -v APP_USER=appA_user \
        -v APP_DB=appA_db \
        -v APP_SCHEMA=appA \
        -v APP_PASSWORD="$(cat /run/secrets/APP_A_PASSWORD)" \
        -f /sql/create_app.sql;
      # Create App B (example second app)
      psql -v ON_ERROR_STOP=1 -d postgres \
        -v APP_USER=appB_user \
        -v APP_DB=appB_db \
        -v APP_SCHEMA=appB \
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
-- psql -v vars: APP_USER, APP_DB, APP_SCHEMA, APP_PASSWORD

-- 1) Create login role (least-privilege)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'APP_USER') THEN
    EXECUTE format(
      'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEROLE NOCREATEDB INHERIT',
      :'APP_USER', :'APP_PASSWORD'
    );
  END IF;
END$$;

-- 2) Create database (owned by current_user, typically postgres)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'APP_DB') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'APP_DB', current_user);
  END IF;
END$$;

\connect :APP_DB

-- 3) Dedicated schema for the app (owned by DB owner)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.schemata WHERE schema_name = :'APP_SCHEMA'
  ) THEN
    EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I', :'APP_SCHEMA', current_user);
  END IF;
END$$;

-- 4) Optional: avoid accidental use of public schema
--    Revoke CREATE on public and set app_user's search_path
DO $$
BEGIN
  -- Revoke CREATE on public for safety (idempotent)
  EXECUTE 'REVOKE CREATE ON SCHEMA public FROM PUBLIC';
  EXECUTE format('ALTER ROLE %I IN DATABASE %I SET search_path = %I, public',
                 :'APP_USER', :'APP_DB', :'APP_SCHEMA');
END$$;

-- 5) Grants (CONNECT, USAGE) and default privileges (future objects)
DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', :'APP_DB', :'APP_USER');
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', :'APP_SCHEMA', :'APP_USER');

  -- Default privs for objects created by DB owner in this schema
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
    :'APP_SCHEMA', :'APP_USER'
  );
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I',
    :'APP_SCHEMA', :'APP_USER'
  );

  -- Bring existing objects under control too
  EXECUTE format(
    'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I',
    :'APP_SCHEMA', :'APP_USER'
  );
  EXECUTE format(
    'GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA %I TO %I',
    :'APP_SCHEMA', :'APP_USER'
  );
END$$;

```
## ADDING A NEW APP
 To add **one new app** (say `myapp`) to `docker-compose.apps.yml`, make **exactly these edits**:

You need to define:
- myapp_user < -- User for myapp
- myapp_db <--- db for myapp
- myapp <- SCHEMA for myapp


1. **Add its secret to `services.dbtool.secrets`:**

```yaml
services:
  dbtool:
    # ...unchanged...
    secrets:
      - POSTGRES_PASSWORD
      - APP_A_PASSWORD
      - APP_B_PASSWORD
      - APP_MYAPP_PASSWORD          # ← add this line
```

2. **Add a new `psql` stanza to `services > dbtool > command` in the doicker-compose.apps.yml:**

```bash
# Create MyApp
psql -v ON_ERROR_STOP=1 -d postgres \
  -v APP_USER=myapp_user \
  -v APP_DB=myapp_db \
  -v APP_SCHEMA=myapp \
  -v APP_PASSWORD="$(cat /run/secrets/APP_MYAPP_PASSWORD)" \
  -f /sql/create_app.sql;
```
Place it after the App B block; keep the trailing semicolon.

3. **Declare the secret at the root `secrets:` section in the doicker-compose.apps.yml:**

```yaml
secrets:
  POSTGRES_PASSWORD:
    file: ./secrets/POSTGRES_PASSWORD
  APP_A_PASSWORD:
    file: ./secrets/APP_A_PASSWORD
  APP_B_PASSWORD:
    file: ./secrets/APP_B_PASSWORD
  APP_MYAPP_PASSWORD:                 # ← add this block
    file: ./secrets/APP_MYAPP_PASSWORD
```



---

### **Usage** 

```bash
# Prepare secrets for each app user:
# add app name to /scripts/gen_secrets.sh after line 25 
#   -> add: gen APP_MYAPP_PASSWORD
# generate secret by running the app
./scripts/gen_secrets.sh

# Run the one-shot job:
docker compose -f docker-compose.apps.yml run --rm dbtool
```

### Your app connects with

```
postgresql://myapp_user:<contents of secrets/APP_MYAPP_PASSWORD>@pgdb:5432/myapp_db?search_path=myapp
```

> That’s it—only those three compose edits (plus the network check). No other changes needed.

---

### Network
 **Ensure the network matches your init stack (so `pgdb` is reachable):**

```yaml
networks:
  pgnet:
    external: true                    # ← must be true if init stack already created it
    name: pgnet                     # optional; add if you named it explicitly in init
```