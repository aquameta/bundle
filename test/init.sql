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
    if ditty.repository_exists('io.pgditty.set_counts') then
        perform ditty.delete_repository('io.pgditty.set_counts');
        raise notice 'DELETING set_counts repo';
    end if;

    if ditty.repository_exists('io.pgditty.unittest') then
        perform ditty.delete_repository('io.pgditty.unittest');
        raise notice 'DELETING unittest repo';
    end if;
end; $$ language plpgsql;
*/

-- begin;
set search_path=public;
