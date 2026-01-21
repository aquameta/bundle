# bundle-tracking

## brief

Tracking registers rows with a repository before they can be staged and committed. Untracked rows are either ignored (shouldn't be versioned) or rogue (orphaned, need tracking or cleanup).

## summary

- `bundle._get_untracked_rows()` - find rows not tracked by any bundle
- `bundle.track_untracked_row('name', row_id)` - track a single row
- `bundle.track_untracked_rows_by_relation('name', relation_id)` - track all rows in a table
- `bundle.untrack_tracked_row('name', row_id)` - remove from tracking
- `bundle.get_tracked_rows_added('name')` - list newly tracked (not yet staged) rows
- Untracked rows: either ignored (see bundle-ignore) or rogue/orphaned

## full

### Understanding Untracked Rows

Untracked rows fall into two categories:

1. **Ignored data** - Tables/rows explicitly excluded from version control (sessions, caches, large data tables). See `bundle-ignore` chunk.

2. **Rogue/orphaned rows** - Rows that should be tracked but aren't. Often created during development and forgotten. Need to be tracked or cleaned up.

```sql
-- Find all untracked rows
select * from bundle._get_untracked_rows();

-- Untracked rows in a specific relation
select * from bundle._get_untracked_rows(
    meta.make_relation_id('widget', 'widget')
);
```

### Tracking Rows

**Track a single row:**
```sql
select bundle.track_untracked_row(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);
```

**Track all rows in a table:**
```sql
select bundle.track_untracked_rows_by_relation(
    'org.aquameta.ui.ide',
    meta.make_relation_id('widget', 'widget')
);
```

### Viewing Tracked Rows

```sql
-- Newly tracked rows (not yet staged)
select * from bundle.get_tracked_rows_added('org.aquameta.ui.ide');

-- All tracked rows (tracked + staged + committed)
select * from bundle.get_tracked_rows('org.aquameta.ui.ide');

-- View across all repos
select * from bundle.tracked_row_added;
```

### Untracking Rows

Remove a row from tracking (only works for newly tracked rows, not committed):

```sql
select bundle.untrack_tracked_row(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);
```

### Tracking Flow

```
Database Row (untracked)
        │
        ▼  track_untracked_row()
Tracked Row (in tracked_rows_added)
        │
        ▼  stage_tracked_row()
Staged Row (in stage_rows_to_add)
        │
        ▼  commit()
Committed Row (in commit.jsonb_rows)
```

### Trackable Relations

A relation must have a primary key and not be ignored:

```sql
select * from bundle.trackable_relation;
```
