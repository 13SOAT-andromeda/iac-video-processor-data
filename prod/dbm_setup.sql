-- Datadog Database Monitoring (DBM) setup for the users-db RDS Postgres
-- instance. Deliberately NOT Terraform: it's a one-time SQL migration
-- against a dedicated application role, not infrastructure. Depends on
-- rds.tf's shared_preload_libraries=pg_stat_statements parameter group
-- (that part IS Terraform — pg_stat_statements can't be enabled by
-- CREATE EXTENSION alone, it must be preloaded at the instance level).
--
-- Run once per fresh RDS instance (AWS Academy Lab resets wipe this).
-- The :datadog_password psql variable must be supplied via -v, e.g.:
--   psql "$DSN" -v datadog_password="$(openssl rand -base64 24)" -f dbm_setup.sql

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE USER datadog WITH PASSWORD :'datadog_password';
ALTER USER datadog SET search_path = public, pg_catalog;
GRANT pg_monitor TO datadog;
GRANT SELECT ON pg_stat_database TO datadog;

CREATE SCHEMA IF NOT EXISTS datadog;
GRANT USAGE ON SCHEMA datadog TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;

-- Lets the Agent run EXPLAIN on behalf of datadog for query samples,
-- without granting datadog blanket execute rights on user tables.
CREATE OR REPLACE FUNCTION datadog.explain_statement(
   l_query TEXT,
   OUT explain JSON
)
RETURNS SETOF JSON AS
$$
DECLARE
curs REFCURSOR;
plan JSON;
BEGIN
   OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
   FETCH curs INTO plan;
   CLOSE curs;
   RETURN QUERY SELECT plan;
END;
$$
LANGUAGE 'plpgsql'
RETURNS NULL ON NULL INPUT
SECURITY DEFINER;
