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
