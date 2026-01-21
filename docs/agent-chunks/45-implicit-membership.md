# implicit-membership

## brief

Rows don't have `bundle_id` columns. Membership is implicit - determined by whether a bundle tracks/commits the row. The bundle points to rows, not rows to bundles.

## summary

- Rows have no FK to bundle - they don't "know" what bundle they're in
- Bundle commits contain `jsonb_rows` array listing row_ids that belong to it
- Membership discovered by asking "is this row_id in this bundle's commit?"
- Same row could theoretically be in multiple bundles (though usually not)
- Pattern used for: `widget.widget`, `web.module`, `widget.bundle_alias`, etc.
- Contrast with explicit membership: row has `bundle_id` FK declaring ownership

## full

### The Pattern

Traditional approach (explicit membership):
```sql
create table widget (
    id uuid primary key,
    bundle_id uuid references bundle.repository(id),  -- "I belong to X"
    name text,
    ...
);
```

Aquameta approach (implicit membership):
```sql
create table widget.widget (
    id uuid primary key,
    name text,
    -- no bundle_id!
    ...
);

-- Membership is in the bundle's commit:
-- bundle.commit.jsonb_rows = [
--   {"schema_name": "widget", "relation_name": "widget", "pk_values": ["uuid-1"]},
--   {"schema_name": "widget", "relation_name": "widget", "pk_values": ["uuid-2"]},
--   ...
-- ]
```

### Why This Pattern?

1. **Rows are portable** - same row could be tracked by different bundles in different contexts

2. **No schema coupling** - `widget.widget` doesn't need to know about the bundle system

3. **Version control is orthogonal** - tracking is a layer on top, not baked into every table

4. **Cleaner data model** - rows contain domain data, not VCS metadata

### Discovering Membership

```sql
-- Which bundle(s) contain this row? Use the helper function:
select * from bundle.get_repository_by_row(
    meta.make_row_id('widget', 'widget', 'id', 'some-widget-uuid')
);
-- Returns: repository_id | repository_name

-- Or manually check a specific bundle:
select exists (
    select 1 from bundle.get_head_commit_rows('org.aquameta.ui.ide') hcr
    where (hcr.row_id->'pk_values'->>0)::uuid = 'widget-uuid-here'
);
```

### Tables Using This Pattern

- `widget.widget` - widgets belong to bundles implicitly
- `web.module` - modules belong to bundles implicitly
- `endpoint.resource` - resources belong to bundles implicitly
- `widget.bundle_alias` - alias mappings belong to bundles implicitly

### Lookup Keys vs Foreign Keys

Tables often have a `bundle_name` text column for **lookup**, not ownership:

```sql
create table widget.bundle_alias (
    bundle_name text not null,  -- lookup key, NOT ownership
    alias text not null,
    target_bundle text not null
);
```

The `bundle_name` column answers "which bundle's aliases are these?" for querying purposes. But the row's **membership** in a bundle is still determined by tracking, not by this column.
