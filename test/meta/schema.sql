select '------------- test/meta/schema.sql ----------------------------------------';

--
-- Test bundle version control on meta.schema (schema-as-data versioning)
--

-- Create test bundle for schema versioning
select bundle.create_repository('test.schema.versioning');

-- Test 1: Create schema first, then track it for versioning
-- Create the schema via meta.schema insert (schema-as-data)
insert into meta.schema (name, id)
values ('test_versioned_schema', meta.make_schema_id('test_versioned_schema'));

-- Now track the created schema row for versioning
select lives_ok(
    $$select bundle.track_untracked_row('test.schema.versioning',
        meta.make_row_id('meta', 'schema', 'id', meta.make_schema_id('test_versioned_schema')::text))$$,
    'Can track a schema row for versioning'
);

-- Verify schema was created in PostgreSQL
select ok(
    (select count(*) from information_schema.schemata where schema_name = 'test_versioned_schema') = 1,
    'Schema created via INSERT into meta.schema'
);

-- Stage and commit the schema creation
select bundle.stage_tracked_row('test.schema.versioning',
    meta.make_row_id('meta', 'schema', 'id', meta.make_schema_id('test_versioned_schema')::text));
select bundle.commit('test.schema.versioning', 'Add test_versioned_schema', 'Test User', 'test@example.com');

-- Verify commit was created
select ok(
    (select count(*) from bundle.commit where repository_id = bundle.repository_id('test.schema.versioning')) = 1,
    'Schema creation committed to bundle'
);

-- Test 2: Version a schema rename operation
update meta.schema
set name = 'test_renamed_schema'
where name = 'test_versioned_schema';

-- Verify rename worked in PostgreSQL
select ok(
    (select count(*) from information_schema.schemata where schema_name = 'test_renamed_schema') = 1,
    'Schema renamed via UPDATE on meta.schema'
);

select ok(
    (select count(*) from information_schema.schemata where schema_name = 'test_versioned_schema') = 0,
    'Old schema name no longer exists'
);

-- Stage and commit the rename
select bundle.stage_tracked_row('test.schema.versioning',
    meta.make_row_id('meta', 'schema', 'id', meta.make_schema_id('test_renamed_schema')::text));
select bundle.commit('test.schema.versioning', 'Rename schema to test_renamed_schema', 'Test User', 'test@example.com');

-- Verify we have 2 commits now
select ok(
    (select count(*) from bundle.commit where repository_id = bundle.repository_id('test.schema.versioning')) = 2,
    'Schema rename committed as second version'
);

-- Test 3: View commit history of schema changes
select results_eq(
    'select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id(''test.schema.versioning''))',
    $$VALUES (2::bigint)$$,
    'Bundle has 2 commits in history'
);

-- Test 4: Test schema deletion and versioning
delete from meta.schema where name = 'test_renamed_schema';

-- Verify deletion worked in PostgreSQL
select ok(
    (select count(*) from information_schema.schemata where schema_name = 'test_renamed_schema') = 0,
    'Schema deleted via DELETE from meta.schema'
);

-- Commit the deletion (this will remove the tracked row)
select bundle.commit('test.schema.versioning', 'Delete renamed schema', 'Test User', 'test@example.com');

-- Verify we have 3 commits total
select ok(
    (select count(*) from bundle.commit where repository_id = bundle.repository_id('test.schema.versioning')) = 3,
    'Schema deletion committed as third version'
);

-- Test 5: Demonstrate that schema history is preserved in bundle
select ok(
    (select count(*) from bundle._get_commit_ancestry(bundle.head_commit_id('test.schema.versioning'))) = 3,
    'Complete schema lifecycle preserved in version history'
);

-- Test commit messages are preserved
select set_has(
    $$select message from bundle.commit
      where repository_id = bundle.repository_id('test.schema.versioning')$$,
    $$VALUES ('Add test_versioned_schema'), ('Rename schema to test_renamed_schema'), ('Delete renamed schema')$$,
    'All schema change commit messages preserved'
);

-- Clean up test bundle
select bundle.delete_repository('test.schema.versioning');

select '------------- end meta/schema.sql ------------------------------------------';
