\timing
create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;

begin;

-- test schema
drop schema if exists delta_test cascade;
create schema delta_test;

set search_path=delta_test, public;

select no_plan();
