select '------------- test/meta/table.sql -----------------------------------------';

--
-- Test bundle version control on meta.table (table-as-data versioning)
--

-- Create test schema and bundle for table versioning
create schema test_table_versioning;
select bundle.create_repository('test.table.versioning');
select bundle.checkout('test.table.versioning');

-- Test 1: Track and version a table creation
select lives_ok(
    $$select bundle.track_untracked_row('test.table.versioning',
        meta.make_row_id('meta', 'table', 'id', meta.make_table_id('test_table_versioning', 'users')::text))$$,
    'Can track a table row for versioning'
);

-- Create the table via meta.table insert (schema-as-data)
insert into meta.table (schema_name, name)
values ('test_table_versioning', 'users');

-- Verify table was created in PostgreSQL
select ok(
    (select count(*) from pg_tables where schemaname = 'test_table_versioning' and tablename = 'users') = 1,
    'Table created via INSERT into meta.table'
);

-- Stage and commit the table creation
select bundle.stage_tracked_row('test.table.versioning',
    meta.make_row_id('meta', 'table', 'id', meta.make_table_id('test_table_versioning', 'users')::text));
select bundle.commit('test.table.versioning', 'Add users table');

-- Test 2: Version a table rename operation
update meta.table
set name = 'people'
where schema_name = 'test_table_versioning' and name = 'users';

-- Verify rename worked in PostgreSQL
select ok(
    (select count(*) from pg_tables where schemaname = 'test_table_versioning' and tablename = 'people') = 1,
    'Table renamed via UPDATE on meta.table'
);

select ok(
    (select count(*) from pg_tables where schemaname = 'test_table_versioning' and tablename = 'users') = 0,
    'Old table name no longer exists'
);

-- Stage and commit the rename (note: id changes with rename)
select bundle.stage_tracked_row('test.table.versioning',
    meta.make_row_id('meta', 'table', 'id', meta.make_table_id('test_table_versioning', 'people')::text));
select bundle.commit('test.table.versioning', 'Rename users table to people');

-- Test 3: Version table with row security toggle
update meta.table
set rowsecurity = true
where schema_name = 'test_table_versioning' and name = 'people';

-- Verify row security was enabled
select ok(
    (select count(*) from pg_tables
     where schemaname = 'test_table_versioning'
       and tablename = 'people'
       and rowsecurity = true) = 1,
    'Row security enabled via UPDATE on meta.table'
);

-- Commit the row security change
select bundle.stage_tracked_row('test.table.versioning',
    meta.make_row_id('meta', 'table', 'id', meta.make_table_id('test_table_versioning', 'people')::text));
select bundle.commit('test.table.versioning', 'Enable row security on people table');

-- Test 4: View commit history of table changes
select results_eq(
    'select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id(''test.table.versioning''))',
    $$VALUES (3::bigint)$$,
    'Bundle has 3 commits in table history'
);

-- Test 5: Test table deletion and versioning
delete from meta.table where schema_name = 'test_table_versioning' and name = 'people';

-- Verify deletion worked in PostgreSQL
select ok(
    (select count(*) from pg_tables where schemaname = 'test_table_versioning' and tablename = 'people') = 0,
    'Table deleted via DELETE from meta.table'
);

-- Commit the deletion
select bundle.commit('test.table.versioning', 'Delete people table');

-- Verify we have 4 commits total
select ok(
    (select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id('test.table.versioning'))) = 4,
    'Complete table lifecycle preserved in version history'
);

-- Test commit messages are preserved
select set_has(
    $$select message from bundle.commit
      where bundle_id = (select id from bundle.bundle where name = 'test.table.versioning')$$,
    $$VALUES ('Add users table'), ('Rename users table to people'), ('Enable row security on people table'), ('Delete people table')$$,
    'All table change commit messages preserved'
);

-- Clean up
select bundle.delete_repository('test.table.versioning');
drop schema test_table_versioning;

select '------------- end meta/table.sql -------------------------------------------';
