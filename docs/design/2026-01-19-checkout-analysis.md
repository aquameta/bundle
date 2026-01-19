# Checkout Flow Analysis

## Overview

Bundle's checkout restores committed rows to the database. Understanding this flow is essential for implementing apply hooks that enable spec tables (like `meta.function_spec`) to create DDL during checkout.

## Data Structures

### Commit Storage

```sql
create table commit (
    id uuid primary key,
    repository_id uuid,
    parent_id uuid,
    jsonb_rows jsonb,    -- array of row_id::text, ordered
    jsonb_fields jsonb,  -- object: row_id::text → {column: value_hash}
    message text,
    commit_time timestamptz
);
```

Key insight: `jsonb_rows` is an **ordered array**. The position of each row in this array determines checkout order.

### Row Identification

```sql
-- row_id structure
{
    "schema_name": "meta",
    "relation_name": "function_spec",
    "pk_column_names": ["id"],
    "pk_values": ["e7e6cc46-b1ac-4667-aaef-33ded9fa5cf0"]
}
```

### Field Storage

Fields are stored as hashes in `jsonb_fields`:
```sql
{
    "<row_id::text>": {
        "column_name": "<value_hash>",
        "another_column": "<value_hash>"
    }
}
```

Value hashes reference blobs in `bundle.blob` table. The `unhash()` function retrieves actual values.

## Core Functions

### _get_commit_rows()

```sql
create function _get_commit_rows(_commit_id uuid)
returns table(_position integer, row_id meta.row_id)
```

Extracts rows from `jsonb_rows` with their position:
- Uses `jsonb_array_elements() with ordinality` to get array index
- Position is 1-indexed, derived from array order
- This is the **authoritative order** for checkout

### _get_commit_fields()

```sql
create function _get_commit_fields(_commit_id uuid)
returns setof field_hash  -- (field_id, value_hash)
```

Extracts all field hashes from `jsonb_fields`. Used to get column values for each row during checkout.

### _checkout_row()

```sql
create function _checkout_row(row_id meta.row_id, fields jsonb, upsert boolean)
returns void
```

Inserts a single row:
1. Unhash each field value (blob hash → actual value via `bundle.unhash()`)
2. Build JSONB object with column names and values
3. Generate INSERT using `jsonb_populate_record()` for type conversion
4. If upsert: add `ON CONFLICT ... DO UPDATE` clause
5. Execute the INSERT

### _checkout()

```sql
create function _checkout(_commit_id uuid, upsert boolean default false)
returns text
```

Main orchestration:
```
1. Validate commit exists
2. Get repository info (id, name, head_commit_id, etc.)

3. FOR each row in commit (ordered by _position):
   a. Aggregate fields: column_name → value_hash
   b. Call _checkout_row(row_id, fields, upsert)

4. Update repository.checkout_commit_id = _commit_id
5. Return success message
```

The query that drives the loop:
```sql
select r.row_id,
       jsonb_object_agg(f.field_id->>'column_name', f.value_hash) as fields
from bundle._get_commit_rows(_commit_id) r
    join bundle._get_commit_fields(_commit_id) f
        on meta.field_id_to_row_id(f.field_id) = r.row_id
group by r.row_id, r._position
order by r._position  -- CRITICAL: maintains commit order
```

### _delete_checkout()

Deletes checked-out rows in **reverse order**:
```sql
for r in select * from bundle._get_commit_rows(_commit_id)
         order by _position desc  -- reverse
loop
    execute format('delete from %I.%I where %s', ...);
end loop;
```

Reverse order handles foreign key dependencies (child rows deleted before parents).

## Row Ordering

### How Order is Established

The commit process (`__commit_stage_rows` in commit.sql) topologically sorts rows by relation:

```sql
-- Get FK-sorted relations
select bundle._topological_sort_relations(
    bundle._get_rowset_relations(stage_rows_to_add)
) into commit_relations;

-- Write rows ordered by their relation's position in sorted list
update bundle.commit
set jsonb_rows = (
    select jsonb_agg(r.row_id) from (
        select row_id
        from ... jsonb_array_elements(stage_rows_to_add) row_id
        order by array_position(commit_relations,
                 meta.row_id_to_relation_id(row_id::meta.row_id))
    ) r
) where id = new_commit_id;
```

This ensures parent tables come before child tables (FK dependency order).

### How Order is Preserved

1. `jsonb_rows` array maintains insertion order
2. `_get_commit_rows()` uses `with ordinality` to extract position
3. `_checkout()` sorts by `_position`
4. Rows restore in exact commit order

### Why Order Matters

Consider a bundle containing:
1. `meta.table_spec` row for table `app.users`
2. Data rows for `app.users`

If checkout processes in wrong order:
```
1. Try to INSERT into app.users  → ERROR: relation does not exist
2. Apply table_spec             → too late
```

Correct order:
```
1. INSERT into meta.table_spec  → row exists in spec table
2. Apply hook                   → CREATE TABLE app.users
3. INSERT into app.users        → works
```

## Apply Hook Integration Point

### Current Flow (Broken for DDL)

```sql
for commit_row in ... order by r._position loop
    perform bundle._checkout_row(...);
end loop;

-- Hooks called here - TOO LATE
perform bundle._apply_checkout_hooks(_commit_id);
```

### Required Flow

```sql
for commit_row in ... order by r._position loop
    perform bundle._checkout_row(commit_row.row_id, commit_row.fields, upsert);

    -- Apply hook immediately if this relation has one
    perform bundle._maybe_apply_row_hook(commit_row.row_id);
end loop;
```

### Hook Table

```sql
create table checkout_apply_hook (
    id uuid primary key,
    relation_id meta.relation_id unique,
    relation_pk_column_names text[] default '{id}',
    apply_function_id meta.function_id
);
```

### Hook Execution

For each row checked out:
1. Check if `relation_id` matches any hook
2. If yes, extract pk values from `row_id`
3. Call `apply_function_id` with those values

Example for `function_spec`:
```sql
-- Row checked out to meta.function_spec with id = 'abc-123'
-- Hook registered: apply_function_id = meta.apply_function_spec(uuid)
-- Executes: SELECT meta.apply_function_spec('abc-123'::uuid)
```

## Delete Checkout and Hooks

When deleting a checkout, we may need **reverse hooks** - to drop DDL before removing spec rows.

Current `_delete_checkout()` iterates in reverse `_position` order. This naturally handles:
1. Delete data rows first (they depend on tables)
2. Delete spec rows last

But we may need hooks that DROP the DDL before the spec row is deleted:
```sql
for r in ... order by _position desc loop
    perform bundle._maybe_apply_delete_hook(r.row_id);  -- DROP TABLE
    execute 'delete from ...';                           -- remove spec row
end loop;
```

## Performance Considerations

### Current: Row-by-Row

Each row = 1 INSERT statement. For large commits, this is slow.

### Future Optimization

Group by relation, batch inserts:
```sql
-- Instead of 1000 individual INSERTs:
INSERT INTO app.users SELECT * FROM jsonb_populate_recordset(...)
```

But this complicates hook ordering. Hooks would need to fire per-relation-batch rather than per-row.

### Hook Performance

Hooks add overhead:
- One lookup per row (is there a hook for this relation?)
- One function call per matching row

Mitigation:
- Cache hook lookups at start of checkout
- Only check relations that have hooks registered

## Open Questions

1. **Delete hooks**: Do we need pre-delete hooks to DROP DDL before removing spec rows?

2. **Batch optimization**: Can we maintain correct hook semantics while batching INSERTs by relation?

3. **Error handling**: If a hook fails mid-checkout, what's the recovery path? The transaction should rollback, but do we need explicit cleanup?

4. **Circular dependencies**: What if `function_spec` A depends on `function_spec` B and vice versa? PostgreSQL's deferred constraints may help, but cross-function cycles are rare.
