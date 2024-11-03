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
create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;

-- clear everything
drop schema if exists shakespeare cascade;
drop schema if exists set_counts cascade;
drop schema if exists pt cascade;


do $$ begin
    if delta.repository_exists('io.pgdelta.set_counts') then
        perform delta.delete_repository('io.pgdelta.set_counts');
        raise notice 'DELETING set_counts repo';
    end if;

    if delta.repository_exists('io.pgdelta.unittest') then
        perform delta.delete_repository('io.pgdelta.unittest');
        raise notice 'DELETING unittest repo';
    end if;
end; $$ language plpgsql;

-- begin;
set search_path=public;
select no_plan();
