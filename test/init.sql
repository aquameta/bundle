\unset ECHO
\set QUIET 1
-- Turn off echo and keep things quiet.

-- Format the output for nice TAP.
\pset format unaligned
\pset tuples_only true
\pset pager off

-- Revert all changes on failure.
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true




-- \timing
create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;


begin;
set search_path=delta_test,public;
select no_plan();
