-- begin;
\timing
create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;

-- sample data via https://github.com/catherinedevlin/opensourceshakespeare
\i data/shakespeare.sql
-- nope, deps: delete from meta.table where schema_name='shakespeare' and name not in ('character');

/*
drop table shakespeare.character_work;
drop table shakespeare.paragraph;
drop table shakespeare.chapter;
drop table shakespeare.work;
drop table shakespeare.wordform;

delete from shakespeare.character where name not ilike 'an%';
*/

-- test schema
create schema delta_test;

set search_path=delta_test, public;

select no_plan();
