-- Deterministic fingerprint of all application tables in ledger/identity.
-- Intended to be run against a source database and a restored database, then
-- diffed. Row text and md5 are stable within the same PostgreSQL version and
-- timezone; CI runs with PGTZ=UTC.
\pset pager off
\pset tuples_only on
\pset fieldsep '|'
\pset format unaligned

CREATE OR REPLACE FUNCTION pg_temp.fp_table(p_schema text, p_table text)
RETURNS TABLE(table_name text, row_count bigint, row_hash text)
LANGUAGE plpgsql AS $$
DECLARE
    sql text;
BEGIN
    sql := format(
        'SELECT %L, count(*)::bigint, md5(coalesce(string_agg(x::text, '''' ORDER BY x::text), ''''))::text FROM %I.%I x',
        p_table, p_schema, p_table
    );
    RETURN QUERY EXECUTE sql;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.fp_sequence(p_schema text, p_sequence text)
RETURNS TABLE(sequence_name text, last_value text, is_called boolean)
LANGUAGE plpgsql AS $$
DECLARE
    sql text;
BEGIN
    sql := format(
        'SELECT %L, last_value::text, is_called FROM %I.%I',
        p_sequence, p_schema, p_sequence
    );
    RETURN QUERY EXECUTE sql;
END;
$$;

SELECT n.nspname || '.' || c.relname || '|' || fp.row_count || '|' || fp.row_hash
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN LATERAL pg_temp.fp_table(n.nspname, c.relname) fp ON true
WHERE n.nspname IN ('ledger', 'identity')
  AND c.relkind = 'r'
ORDER BY 1;

SELECT n.nspname || '.' || c.relname || '|' || fp.last_value || '|' || fp.is_called
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN LATERAL pg_temp.fp_sequence(n.nspname, c.relname) fp ON true
WHERE n.nspname IN ('ledger', 'identity')
  AND c.relkind = 'S'
ORDER BY 1;
