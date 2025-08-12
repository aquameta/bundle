--
-- Bundle meta catalog versioning tests
-- Testing schema-as-data: creating and modifying schema through meta catalog inserts
--

-------------------------------------------------------------------------------
-- Setup: Create a test repository
-------------------------------------------------------------------------------
select bundle.create_repository('test.meta.schema') as test_repository_id;

-- Create the test schema first (required before creating tables in it)
insert into meta.schema (name, id)
values ('test', meta.make_schema_id('test'));

-------------------------------------------------------------------------------
-- Test 1: Create a table via meta.table insert
-------------------------------------------------------------------------------
-- Insert a row into meta.table to represent a new table
insert into meta.table (schema_name, name)
values ('test', 'widget');

-- Track this meta.table row
select bundle.track_untracked_row(
    'test.meta.schema',
    meta.make_row_id('meta', 'table', array['id'],
        array[(select id::text from meta.table where schema_name = 'test' and name = 'widget')])
);

-- Stage and commit the table creation
select bundle.stage_tracked_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Create widget table', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 2: Add columns to the table via meta.column inserts
-------------------------------------------------------------------------------
-- Get the table_id for our widget table
with widget_table as (
    select id from meta.table where schema_name = 'test' and name = 'widget'
)
-- Insert columns
insert into meta.column (schema_name, relation_name, name, type_name, nullable, position)
select 'test', 'widget', 'id', 'uuid', false, 1 from widget_table
union all
select 'test', 'widget', 'name', 'text', false, 2 from widget_table
union all
select 'test', 'widget', 'html', 'text', true, 3 from widget_table
union all
select 'test', 'widget', 'css', 'text', true, 4 from widget_table
union all
select 'test', 'widget', 'javascript', 'text', true, 5 from widget_table
union all
select 'test', 'widget', 'created_at', 'timestamp', false, 6 from widget_table;

-- Track the column rows
select bundle.track_untracked_rows_by_relation(
    'test.meta.schema',
    meta.make_relation_id('meta', 'column')
);

-- Stage and commit the column additions
select bundle.stage_tracked_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Add columns to widget table', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 3: Add a primary key constraint via meta.constraint inserts
-------------------------------------------------------------------------------
insert into meta.constraint (schema_name, relation_name, name, type, definition)
values ('test', 'widget', 'widget_pkey', 'p', 'PRIMARY KEY (id)');

-- Track the constraint
select bundle.track_untracked_row(
    'test.meta.schema',
    meta.make_row_id('meta', 'constraint', array['id'],
        array[(select id::text from meta.constraint
               where schema_name = 'test' and relation_name = 'widget' and name = 'widget_pkey')])
);

-- Stage and commit the constraint
select bundle.stage_tracked_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Add primary key to widget table', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 4: Modify a column (make it nullable) via update
-------------------------------------------------------------------------------
update meta.column
set nullable = true
where schema_name = 'test' and relation_name = 'widget' and name = 'name';

-- Stage the field change
select bundle.stage_updated_fields('test.meta.schema');
select bundle.commit('test.meta.schema', 'Make widget.name nullable', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 5: Add an index via meta.index insert
-------------------------------------------------------------------------------
insert into meta.index (schema_name, name, relation_name, definition)
values ('test', 'widget_name_idx', 'widget', 'CREATE INDEX widget_name_idx ON test.widget(name)');

-- Track the index
select bundle.track_untracked_row(
    'test.meta.schema',
    meta.make_row_id('meta', 'index', array['id'],
        array[(select id::text from meta.index
               where schema_name = 'test' and name = 'widget_name_idx')])
);

-- Stage and commit the index
select bundle.stage_tracked_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Add index on widget.name', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 6: Create a second table with a foreign key
-------------------------------------------------------------------------------
-- Create widget_version table
insert into meta.table (schema_name, name)
values ('test', 'widget_version');

-- Add columns to widget_version
insert into meta.column (schema_name, relation_name, name, type_name, nullable, position)
values
    ('test', 'widget_version', 'id', 'uuid', false, 1),
    ('test', 'widget_version', 'widget_id', 'uuid', false, 2),
    ('test', 'widget_version', 'version', 'integer', false, 3),
    ('test', 'widget_version', 'created_at', 'timestamp', false, 4);

-- Add foreign key constraint
insert into meta.foreign_key (
    schema_name, relation_name, name,
    from_column, to_schema, to_relation, to_column
)
values (
    'test', 'widget_version', 'widget_version_widget_id_fkey',
    'widget_id', 'test', 'widget', 'id'
);

-- Track all the new meta rows
select bundle.track_untracked_rows_by_relation('test.meta.schema', meta.make_relation_id('meta', 'table'));
select bundle.track_untracked_rows_by_relation('test.meta.schema', meta.make_relation_id('meta', 'column'));
select bundle.track_untracked_rows_by_relation('test.meta.schema', meta.make_relation_id('meta', 'foreign_key'));

-- Stage and commit
select bundle.stage_tracked_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Create widget_version table with foreign key', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Test 7: Drop a column via delete
-------------------------------------------------------------------------------
delete from meta.column
where schema_name = 'test' and relation_name = 'widget' and name = 'css';

-- Stage the deletion
select bundle.stage_deleted_rows('test.meta.schema');
select bundle.commit('test.meta.schema', 'Drop widget.css column', 'Test User', 'test@example.com');

-------------------------------------------------------------------------------
-- Verify: Check the commit history
-------------------------------------------------------------------------------
select 'Schema evolution commits:' as info;
select c.id, c.message, c.timestamp
from bundle.commit c
join bundle.repository r on c.repository_id = r.id
where r.name = 'test.meta.schema'
order by c.timestamp;

-- Show what's tracked
select 'Tracked schema objects:' as info;
select
    row_id->>'relation_name' as meta_table,
    count(*) as tracked_rows
from bundle.get_tracked_rows('test.meta.schema')
group by row_id->>'relation_name'
order by meta_table;

-- Show the bundle status
select bundle.status('test.meta.schema', true);

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------
-- Note: We're NOT dropping the actual test.widget tables because they don't
-- exist yet (meta triggers not implemented). We're just tracking the meta rows.

-- Delete the test repository
select bundle.delete_repository('test.meta.schema');

-- Clean up meta catalog rows (since triggers didn't create real tables)
delete from meta.foreign_key where schema_name = 'test';
delete from meta.constraint where schema_name = 'test';
delete from meta.index where schema_name = 'test';
delete from meta.column where schema_name = 'test';
delete from meta.table where schema_name = 'test';
