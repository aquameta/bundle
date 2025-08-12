------------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------------
/*
\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
*/

create extension if not exists hstore schema public;
-- NOTE: disabled for compatibility
-- create extension if not exists "pg_uuidv7" schema public;
create extension if not exists "uuid-ossp" schema public;
create extension if not exists pgcrypto schema public;

-- reset stats
-- NOTE: disabled for compatibility
-- create extension if not exists pg_stat_statements schema public;
-- select public.pg_stat_statements_reset();

-- meta is installed directly by run.sh, not as an extension

-- begin;

create schema bundle;
set search_path=bundle;

