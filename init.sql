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

create schema delta;
set search_path=delta;



-- TODO: where does this go?
create or replace function exec(statements text[]) returns setof record as $$
   declare
       statement text;
   begin
       foreach statement in array statements loop
           raise debug 'EXEC statement: %', statement;
           return query execute statement;
       end loop;
    end;
$$ language plpgsql volatile returns null on null input;
