begin;
create extension if not exists pgtap schema public;

-- sample data via https://github.com/catherinedevlin/opensourceshakespeare
\i shakespeare.sql
-- delete from meta.table where schema_name='shakespeare' and name in ('paragraph', 'wordform');

-- test schema
create schema delta_test;

set search_path=delta_test, public;

select no_plan();
