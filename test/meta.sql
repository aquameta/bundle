--
-- Bundle meta catalog versioning tests
-- Testing schema-as-data: creating and modifying schema through meta catalog inserts
--

-------------------------------------------------------------------------------
-- Setup: Create a test repository
-------------------------------------------------------------------------------
select bundle.create_repository('test.meta.schema') as test_repository_id;

-- Create the test schema first (required before creating tables in it)
insert into meta.schema (name)
values ('test');

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
-- Insert columns (meta.column uses relation_name)
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
-- Test 3: Add a primary key constraint via meta.constraint_primary_key insert
-------------------------------------------------------------------------------
insert into meta.constraint_primary_key (schema_name, table_name, name, columns)
values ('test', 'widget', 'widget_pkey',
    ARRAY[meta.make_column_id('test', 'widget', 'id')]::meta.column_id[]);

-- Track the constraint
select bundle.track_untracked_row(
    'test.meta.schema',
    meta.make_row_id('meta', 'constraint_primary_key', array['id'],
        array[(select id::text from meta.constraint_primary_key
               where schema_name = 'test' and table_name = 'widget' and name = 'widget_pkey')])
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
insert into meta.index (schema_name, name, table_name, columns)
values ('test', 'widget_name_idx', 'widget',
    ARRAY[meta.make_column_id('test', 'widget', 'name')]::meta.column_id[]);

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

-- Add columns to widget_version (meta.column uses relation_name)
insert into meta.column (schema_name, relation_name, name, type_name, nullable, position)
values
    ('test', 'widget_version', 'id', 'uuid', false, 1),
    ('test', 'widget_version', 'widget_id', 'uuid', false, 2),
    ('test', 'widget_version', 'version', 'integer', false, 3),
    ('test', 'widget_version', 'created_at', 'timestamp', false, 4);

-- Add foreign key constraint
insert into meta.foreign_key (
    schema_name, table_name, name,
    from_columns, to_schema_name, to_table_name, to_columns
)
values (
    'test', 'widget_version', 'widget_version_widget_id_fkey',
    ARRAY[meta.make_column_id('test', 'widget_version', 'widget_id')]::meta.column_id[],
    'test', 'widget',
    ARRAY[meta.make_column_id('test', 'widget', 'id')]::meta.column_id[]
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
select c.id, c.message, c.created_at
from bundle.commit c
join bundle.repository r on c.repository_id = r.id
where r.name = 'test.meta.schema'
order by c.created_at;

-- Show what's tracked (only if repository exists)
select 'Tracked schema objects:' as info;
select
    case
        when not exists(select 1 from bundle.repository where name = 'test.meta.schema')
        then 'Repository cleaned up'
        else string_agg(
            coalesce(t.row_id->>'relation_name', t.row_id->>'table_name') || ': ' || count(*)::text,
            ', '
        )
    end as tracked_summary
from (
    select row_id
    from bundle.get_tracked_rows('test.meta.schema')
    where exists(select 1 from bundle.repository where name = 'test.meta.schema')
) t
group by coalesce(t.row_id->>'relation_name', t.row_id->>'table_name');

-- Show the bundle status (only if repository exists)
select case when exists(select 1 from bundle.repository where name = 'test.meta.schema')
    then bundle.status('test.meta.schema', true)
    else 'Repository cleaned up'::text
end as status;

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------
-- Note: The meta triggers DO create real tables, so we need to clean up properly

-- Clean up (don't worry about errors if objects don't exist)
do $$
begin
    -- Delete commits first
    delete from bundle.commit
    where repository_id = (select id from bundle.repository where name = 'test.meta.schema');

    -- Delete the test repository
    perform bundle.delete_repository('test.meta.schema');

    -- Clean up meta catalog rows
    delete from meta.foreign_key where schema_name = 'test';
    delete from meta.index where schema_name = 'test';
    delete from meta.column where schema_name = 'test' and relation_name is not null;
    delete from meta.table where schema_name = 'test' and name in ('widget', 'widget_version');
    delete from meta.schema where name = 'test';
exception when others then
    -- Ignore errors during cleanup
    null;
end $$;
