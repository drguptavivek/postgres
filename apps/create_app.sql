\set ON_ERROR_STOP on

-- 1) Ensure role with least-privilege attributes and password
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'APP_USER') THEN
    'CREATE ROLE ' || quote_ident(:'APP_USER') ||
    ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD ' ||
    quote_literal(:'APP_PASSWORD')
  ELSE
    'ALTER ROLE ' || quote_ident(:'APP_USER') ||
    ' WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD ' ||
    quote_literal(:'APP_PASSWORD')
END;
\gexec

-- 2) Ensure database (owned by role)
SELECT 'CREATE DATABASE ' || quote_ident(:'APP_DB') ||
       ' OWNER ' || quote_ident(:'APP_USER')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'APP_DB');
\gexec

-- 3) DB-level settings: search_path
SELECT 'ALTER DATABASE ' || quote_ident(:'APP_DB') ||
       ' SET search_path = ' || quote_literal(:'APP_SCHEMA') || ', public';
\gexec

-- Restrict CONNECT on the app DB to only the app user
SELECT 'REVOKE CONNECT ON DATABASE ' || quote_ident(:'APP_DB') || ' FROM PUBLIC';
\gexec
SELECT 'GRANT CONNECT ON DATABASE ' || quote_ident(:'APP_DB') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

-- 4) Connect into the target DB
\connect :APP_DB

-- 4a) Hygiene on public schema
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 5) Ensure application schema (owned by app user)
SELECT 'CREATE SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' AUTHORIZATION ' || quote_ident(:'APP_USER')
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.schemata WHERE schema_name = :'APP_SCHEMA'
);
\gexec

-- 6) Grants within application schema
SELECT 'GRANT USAGE ON SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

SELECT 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

SELECT 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' TO ' || quote_ident(:'APP_USER');
\gexec

-- Default privileges for future objects
SELECT 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' GRANT ALL ON TABLES TO ' || quote_ident(:'APP_USER');
\gexec
SELECT 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(:'APP_SCHEMA') ||
       ' GRANT ALL ON SEQUENCES TO ' || quote_ident(:'APP_USER');
\gexec

-- 7) Deny app user from connecting to system DBs (use quoted identifiers)
\connect postgres
SELECT 'REVOKE CONNECT ON DATABASE postgres FROM PUBLIC, '  || quote_ident(:'APP_USER');
\gexec
SELECT 'REVOKE CONNECT ON DATABASE template1 FROM PUBLIC, ' || quote_ident(:'APP_USER');
\gexec
-- template0 remains non-connectable
