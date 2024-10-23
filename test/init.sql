\timing
create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;


begin;
set search_path=delta_test,public;
select no_plan();
