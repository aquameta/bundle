-- Test checkout functionality for schema-as-data

begin;

select plan(10);

-- Create a test repository
select bundle.create_repository('test.checkout.schema_as_data');

-- Test 1: Create a schema via meta.schema
insert into meta.schema (name) values ('checkout_test');
select has_schema('checkout_test', 'Schema created via meta.schema');

-- Test 2: Create a table via meta.table
insert into meta.table (schema_name, name) values ('checkout_test', 'test_table');
select has_table('checkout_test', 'test_table', 'Table created via meta.table');

-- Test 3: Add columns via meta.column
insert into meta.column (schema_name, relation_name, name, type_name) 
values 
    ('checkout_test', 'test_table', 'id', 'integer'),
    ('checkout_test', 'test_table', 'name', 'text'),
    ('checkout_test', 'test_table', 'created_at', 'timestamp');

select has_column('checkout_test', 'test_table', 'id', 'Column id created');
select has_column('checkout_test', 'test_table', 'name', 'Column name created');
select has_column('checkout_test', 'test_table', 'created_at', 'Column created_at created');

-- Test 4: Track and commit these schema objects
select bundle.track_untracked_row(
    'test.checkout.schema_as_data',
    meta.make_row_id('meta', 'schema', 'id', '{"name": "checkout_test"}')
);

select bundle.track_untracked_row(
    'test.checkout.schema_as_data',
    meta.make_row_id('meta', 'table', 'id', '{"name": "test_table", "schema_name": "checkout_test"}')
);

-- Track all three columns
select bundle.track_untracked_row(
    'test.checkout.schema_as_data',
    meta.make_row_id('meta', 'column', 'id', '{"name": "id", "schema_name": "checkout_test", "relation_name": "test_table"}')
);

select bundle.track_untracked_row(
    'test.checkout.schema_as_data',
    meta.make_row_id('meta', 'column', 'id', '{"name": "name", "schema_name": "checkout_test", "relation_name": "test_table"}')
);

select bundle.track_untracked_row(
    'test.checkout.schema_as_data',
    meta.make_row_id('meta', 'column', 'id', '{"name": "created_at", "schema_name": "checkout_test", "relation_name": "test_table"}')
);

-- Stage all tracked rows
select bundle.stage_tracked_rows('test.checkout.schema_as_data');

-- Commit the schema objects
select bundle.commit(
    'test.checkout.schema_as_data', 
    'Test checkout: schema and table', 
    'Test User', 
    'test@example.com'
);

select pass('Schema objects tracked and committed');

-- Test 5: Drop the schema (which drops the table and columns)
drop schema checkout_test cascade;
select hasnt_schema('checkout_test', 'Schema dropped');

-- Test 6: Checkout the commit to recreate the schema
select bundle.checkout('test.checkout.schema_as_data');
select pass('Checkout executed');

-- Test 7: Verify schema was recreated
select has_schema('checkout_test', 'Schema recreated by checkout');

-- Test 8: Verify table was recreated
select has_table('checkout_test', 'test_table', 'Table recreated by checkout');

select * from finish();
rollback;