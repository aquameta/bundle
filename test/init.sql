select '-------------- init.sql -----------------------------------------------';
\unset ECHO
\set QUIET 1
-- Turn off echo and keep things quiet.

-- Format the output for nice TAP.
\pset format unaligned
\pset tuples_only true
\pset pager off

-- Revert all changes on failure.
-- \set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

-- \timing
create extension if not exists pgtap schema public;

/*
do $$ begin
    if bundle.repository_exists('io.pgbundle.set_counts') then
        perform bundle.delete_repository('io.pgbundle.set_counts');
        raise notice 'DELETING set_counts repo';
    end if;

    if bundle.repository_exists('io.pgbundle.unittest') then
        perform bundle.delete_repository('io.pgbundle.unittest');
        raise notice 'DELETING unittest repo';
    end if;
end; $$ language plpgsql;
*/

-- begin;
set search_path=public;
