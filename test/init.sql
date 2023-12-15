begin;
create extension if not exists pgtap schema public;

-- sample data via https://github.com/catherinedevlin/opensourceshakespeare
\i shakespeare.sql
-- delete from meta.table where schema_name='shakespeare' and name in ('paragraph', 'wordform');

-- test schema
create schema delta_test;

set search_path=delta_test, public;

select no_plan();

/*
\set repository_id '\'9caeb540-8ad5-11e4-b4a9-0800200c9a66\''

-- Test vars store temporary variables used internally for testing
create table delta_test.test_vars (
    id serial primary key,
    starting_untracked_rows integer
);
insert into delta_test.test_vars (starting_untracked_rows) values (NULL);

-- REPO_SUMMARY
--
-- A repo_summary is a custom type and utility function that holds the number
-- of rows in the various tables in the system.  We use it to take
-- actions and then quickly compare it to expected row count totals.

create type repo_summary as (
    commit integer,
    head_commit_row integer,
    head_commit_field integer,
    stage_row_added  integer,
    stage_row_deleted integer,
    stage_field_changed integer,
    offstage_row_deleted integer,
    offstage_field_changed integer,
    untracked_row integer
);

create function repo_summary (in repsitory_name text, out result repo_summary) as $$
    declare
        _bundle_id uuid;
        starting_untracked_rows integer;
    begin
        select into _bundle_id id from delta.repository_id(repository_name);
        select into starting_untracked_rows v.starting_untracked_rows from test_vars v;
        select into result
            (select count(*)::integer from delta.commit c
                join delta.rowset r on c.rowset_id=r.id where c.repository_id=_repository_id),
            (select count(*)::integer from delta.repository.head_commit_row r where r.repository_id=_repository_id),
            (select count(*)::integer from delta.stage_row_added r where r.repository_id=_repository_id),
            (select count(*)::integer from delta.stage_row_deleted r where r.repository_id=_repository_id),
            (select count(*)::integer from delta.stage_field_changed r where r.repository_id=_repository_id),
            (select count(*)::integer from delta.offstage_row_deleted r where r.repository_id=_repository_id),
            (select count(*)::integer from delta.offstage_field_changed r where r.repository_id=_repository_id),
            (select (count(*)::integer - starting_untracked_rows) from delta.untracked_row r);
    end;
$$ language plpgsql;

-- setup our counter of starting untracked rows
update test_vars set starting_untracked_rows = (select count(*)::integer from delta.untracked_row);


-------------------------------------------------------------------------------
-- TEST 1: no bundle
-------------------------------------------------------------------------------
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        0, -- commit
        0, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'No repository yet, everything should be zeros'
);

*/
