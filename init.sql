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
create extension if not exists "pg_uuidv7" schema public;
create extension if not exists pgcrypto schema public;

-- reset stats
create extension if not exists pg_stat_statements schema public;
select public.pg_stat_statements_reset();

create extension if not exists meta version '0.5.0';
create extension if not exists meta_triggers version '0.5.0';

begin;

create schema ditty;
set search_path=ditty;

