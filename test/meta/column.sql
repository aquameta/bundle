select '------------- test/meta/column.sql ----------------------------------------';

--
-- Test bundle version control on meta.column (column-as-data versioning)
--

-- Create test schema, table and bundle for column versioning
create schema test_column_versioning;
create table test_column_versioning.test_table ();

select bundle.create_repository('test.column.versioning');
select bundle.checkout('test.column.versioning');

-- Test 1: Track and version a column creation
select lives_ok(
    $$select bundle.track_untracked_row('test.column.versioning',
        meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'id')::text))$$,
    'Can track a column row for versioning'
);

-- Create the column via meta.column insert (schema-as-data)
insert into meta.column (schema_name, relation_name, name, type_name, nullable, id)
values ('test_column_versioning', 'test_table', 'id', 'serial', false,
        meta.make_column_id('test_column_versioning', 'test_table', 'id'));

-- Verify column was created in PostgreSQL
select has_column('test_column_versioning'::name, 'test_table'::name, 'id'::name,
    'Column created via INSERT into meta.column');

-- Stage and commit the column creation
select bundle.stage_tracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'id')::text));
select bundle.commit('test.column.versioning', 'Add id column');

-- Test 2: Version adding another column
insert into meta.column (schema_name, relation_name, name, type_name, nullable, "default", id)
values ('test_column_versioning', 'test_table', 'name', 'text', false, '''Unknown''',
        meta.make_column_id('test_column_versioning', 'test_table', 'name'));

-- Track and stage the new column
select bundle.track_untracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'name')::text));
select bundle.stage_tracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'name')::text));
select bundle.commit('test.column.versioning', 'Add name column with default');

-- Verify column exists with default
select has_column('test_column_versioning'::name, 'test_table'::name, 'name'::name,
    'Name column created with default value');

-- Test 3: Version a column type change
update meta.column
set type_name = 'varchar(255)'
where schema_name = 'test_column_versioning'
  and relation_name = 'test_table'
  and name = 'name';

-- Stage and commit the type change
select bundle.stage_tracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'name')::text));
select bundle.commit('test.column.versioning', 'Change name column to varchar(255)');

-- Verify type change worked
select ok(
    (select data_type from information_schema.columns
     where table_schema = 'test_column_versioning'
       and table_name = 'test_table'
       and column_name = 'name') = 'character varying',
    'Column type changed via UPDATE on meta.column'
);

-- Test 4: Version a column rename
update meta.column
set name = 'full_name'
where schema_name = 'test_column_versioning'
  and relation_name = 'test_table'
  and name = 'name';

-- Stage and commit the rename (note: id changes with rename)
select bundle.stage_tracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'full_name')::text));
select bundle.commit('test.column.versioning', 'Rename name column to full_name');

-- Verify rename worked
select has_column('test_column_versioning'::name, 'test_table'::name, 'full_name'::name,
    'Column renamed via UPDATE on meta.column');

-- Test 5: Version nullability change
update meta.column
set nullable = true
where schema_name = 'test_column_versioning'
  and relation_name = 'test_table'
  and name = 'full_name';

-- Stage and commit the nullability change
select bundle.stage_tracked_row('test.column.versioning',
    meta.make_row_id('meta', 'column', 'id', meta.make_column_id('test_column_versioning', 'test_table', 'full_name')::text));
select bundle.commit('test.column.versioning', 'Make full_name nullable');

-- Verify nullability changed
select ok(
    (select is_nullable from information_schema.columns
     where table_schema = 'test_column_versioning'
       and table_name = 'test_table'
       and column_name = 'full_name') = 'YES',
    'Column nullability changed via UPDATE on meta.column'
);

-- Test 6: View commit history of column changes
select results_eq(
    'select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id(''test.column.versioning''))',
    $$VALUES (5::bigint)$$,
    'Bundle has 5 commits in column history'
);

-- Test 7: Test column deletion and versioning
delete from meta.column
where schema_name = 'test_column_versioning'
  and relation_name = 'test_table'
  and name = 'full_name';

-- Verify deletion worked in PostgreSQL
select ok(
    (select count(*) from information_schema.columns
     where table_schema = 'test_column_versioning'
       and table_name = 'test_table'
       and column_name = 'full_name') = 0,
    'Column deleted via DELETE from meta.column'
);

-- Commit the deletion
select bundle.commit('test.column.versioning', 'Delete full_name column');

-- Verify we have 6 commits total
select ok(
    (select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id('test.column.versioning'))) = 6,
    'Complete column lifecycle preserved in version history'
);

-- Test commit messages are preserved
select set_has(
    $$select message from bundle.commit
      where bundle_id = (select id from bundle.bundle where name = 'test.column.versioning')$$,
    $$VALUES
        ('Add id column'),
        ('Add name column with default'),
        ('Change name column to varchar(255)'),
        ('Rename name column to full_name'),
        ('Make full_name nullable'),
        ('Delete full_name column')$$,
    'All column change commit messages preserved'
);

-- Clean up
select bundle.delete_repository('test.column.versioning');
drop schema test_column_versioning cascade;

select '------------- end meta/column.sql -----------------------------------------';
