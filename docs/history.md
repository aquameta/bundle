# Bundle History (Time Travel)

Query historical row and field data from any commit.

## Quick Start

```sql
-- Get a widget as it was 2 commits ago
select * from bundle.get_row_at_commit(
    'org.aquameta.ui.ide', -2,
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid'),
    null::widget.widget
);

-- Get all widgets at HEAD
select * from bundle.get_rows_at_commit(
    'org.aquameta.ui.ide', 0,
    meta.make_relation_id('widget', 'widget'),
    null::widget.widget
);

-- Get a field value at a specific commit
select bundle.get_field_at_commit(
    'org.aquameta.ui.ide', 0,
    meta.make_field_id('widget', 'widget', 'js', array['id'], array['some-uuid'])
);
```

## Public API

### By Offset

Use integer offsets from HEAD: `0` = HEAD, `-1` = parent, `-2` = grandparent, etc.

```sql
-- Single row
select * from bundle.get_row_at_commit(
    repository_name text,
    offset int,              -- 0, -1, -2, ...
    row_id meta.row_id,
    null::target_table       -- type hint
);

-- All rows from a table
select * from bundle.get_rows_at_commit(
    repository_name text,
    offset int,
    relation_id meta.relation_id,
    null::target_table
);

-- Single field value
select bundle.get_field_at_commit(
    repository_name text,
    offset int,
    field_id meta.field_id
) returns text;
```

### By Timestamp

Query data as it was at a specific point in time. Returns the most recent commit at or before the given timestamp.

```sql
-- Widgets as of yesterday
select * from bundle.get_rows_at_commit(
    'org.aquameta.ui.ide',
    now() - interval '1 day',
    meta.make_relation_id('widget', 'widget'),
    null::widget.widget
);

-- A row as of a specific date
select * from bundle.get_row_at_commit(
    'my.bundle',
    '2024-01-15 14:30:00'::timestamptz,
    meta.make_row_id('schema', 'table', 'id', 'value'),
    null::schema.table
);
```

## Internal API

Lower-level functions that take commit UUID directly.

### JSONB Functions

Return raw JSONB objects (useful for dynamic/untyped access):

```sql
-- Single row as JSONB
select bundle._get_jsonb_row_at_commit(commit_id uuid, row_id meta.row_id)
returns jsonb;

-- All rows as JSONB
select * from bundle._get_jsonb_rows_at_commit(commit_id uuid, relation_id meta.relation_id)
returns setof jsonb;

-- Single field as text
select bundle._get_jsonb_field_at_commit(commit_id uuid, field_id meta.field_id)
returns text;
```

### Typed Record Functions

Return actual table row types via `jsonb_populate_record`:

```sql
-- Single row as record
select * from bundle._get_row_at_commit(
    commit_id uuid,
    row_id meta.row_id,
    null::target_table
) returns anyelement;

-- All rows as records
select * from bundle._get_rows_at_commit(
    commit_id uuid,
    relation_id meta.relation_id,
    null::target_table
) returns setof anyelement;
```

## Examples

### Compare Code Across Commits

```sql
-- Widget JS size at HEAD vs 3 commits ago
select 'HEAD' as ver, name, length(js) as js_size
from bundle.get_rows_at_commit('org.aquameta.ui.ide', 0, meta.make_relation_id('widget', 'widget'), null::widget.widget)
where name = 'ide-app'
union all
select 'HEAD~3', name, length(js)
from bundle.get_rows_at_commit('org.aquameta.ui.ide', -3, meta.make_relation_id('widget', 'widget'), null::widget.widget)
where name = 'ide-app';
```

### View Historical Field Content

```sql
-- Get the CSS as it was last week
select bundle.get_field_at_commit(
    'org.aquameta.ui.ide',
    now() - interval '1 week',
    meta.make_field_id('widget', 'widget', 'css', array['id'], array['0699d674-4c99-4c80-85e4-ebeba2014d0f'])
);
```

### Find Commit History

```sql
-- List recent commits for a bundle
select id, left(message, 50) as message, commit_time
from bundle.commit c
join bundle.repository r on c.repository_id = r.id
where r.name = 'org.aquameta.ui.ide'
order by commit_time desc
limit 10;
```

## Notes

- Positive offsets error (no time travel to the future)
- If a row doesn't exist in a commit, typed functions return a record with all NULL fields
- Field values are stored as JSONB text, so `get_field_at_commit` returns the decoded text value
- Timestamp queries find the most recent commit at or before the given time
