begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

-- select plan(115);
select * from no_plan();

 
\set repo_id '\'9caeb540-8ad5-11e4-b4a9-0800200c9a66\''
