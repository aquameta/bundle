------------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------------

create extension if not exists hstore schema public;
create extension if not exists "pg_uuidv7" schema public;
create extension if not exists pgcrypto schema public;

create extension if not exists meta version '0.5.0';
create extension if not exists meta_triggers;

-- begin;

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
