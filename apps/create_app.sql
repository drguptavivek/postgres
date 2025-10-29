\set ON_ERROR_STOP on

-- 1) Ensure role (create or rotate password)
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'APP_USER')
    THEN 'CREATE ROLE ' || quote_ident(:'APP_USER') ||
         ' LOGIN PASSWORD ' || quote_literal(:'APP_PASSWORD')
  ELSE
    'ALTER ROLE ' || quote_ident(:'APP_USER') ||
         ' WITH PASSWORD ' || quote_literal(:'APP_PASSWORD')
END;
\gexec

-- 2) Ensure database (owned by role)
SELECT 'CREATE DATABASE ' || quote_ident(:'APP_DB') ||
       ' OWNER ' || quote_ident(:'APP_USER')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'APP_DB');
\gexec

-- 3) DB-level settings
SELECT 'ALTER DATABASE ' || quote_ident(:'APP_DB') ||
       ' SET search_path = ' || quote_literal(:'APP_SCHEMA') || ', public';
\gexec

-- 4) Connect into target DB
\connect :APP_DB

-- 5) Ensure schema (owned by role)
SELECT 'CREATE SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' AUTHORIZATION ' || quote_ident(:'APP_USER')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.schemata WHERE schema_name = :'APP_SCHEMA'
);
\gexec

-- 6) Grants
SELECT 'GRANT USAGE ON SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

SELECT 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

SELECT 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

-- 7) Default privileges for future objects
SELECT 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' GRANT ALL ON TABLES TO ' || quote_ident(:'APP_USER');
\gexec

SELECT 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' GRANT ALL ON SEQUENCES TO ' || quote_ident(:'APP_USER');
\gexec
