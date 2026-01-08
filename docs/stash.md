# Bundle Stash

Save uncommitted changes temporarily and restore them later. Similar to `git stash`.

## Quick Start

```sql
-- Save all uncommitted changes
select bundle.stash('my-bundle', 'WIP: feature work');

-- List stashes
select * from bundle.stash_list('my-bundle');

-- Restore most recent stash (removes it)
select bundle.stash_pop('my-bundle');

-- Or apply without removing
select bundle.stash_apply('my-bundle');
```

## Functions

### Creating Stashes

**`bundle.stash(repository_name, message)`** - Stash all uncommitted changes
```sql
select bundle.stash('org.example.app', 'Saving work before switching tasks');
```

**`bundle.stash_rows(repository_name, row_ids, message)`** - Stash specific rows only
```sql
select bundle.stash_rows('org.example.app',
    '[{"schema_name":"widget","relation_name":"widget",...}]'::jsonb,
    'Just the widget changes');
```

### Restoring Stashes

**`bundle.stash_pop(repository_name, force)`** - Apply most recent stash and delete it
```sql
select bundle.stash_pop('org.example.app');
```

**`bundle.stash_apply(repository_name, stash_id, force)`** - Apply stash without deleting
```sql
-- Apply most recent
select bundle.stash_apply('org.example.app');

-- Apply specific stash
select bundle.stash_apply('org.example.app', 'a1b2c3d4-...'::uuid);
```

### Managing Stashes

**`bundle.stash_list(repository_name)`** - List all stashes
```sql
select id, message, created_at, offstage_fields, offstage_rows
from bundle.stash_list('org.example.app');
```

**`bundle.stash_show(stash_id)`** - Show stash contents
```sql
select category, item_type, identifier, value_preview
from bundle.stash_show('a1b2c3d4-...'::uuid);
```

**`bundle.stash_drop(stash_id)`** - Delete stash without applying
```sql
select bundle.stash_drop('a1b2c3d4-...'::uuid);
```

**`bundle.stash_clear(repository_name)`** - Delete all stashes
```sql
select bundle.stash_clear('org.example.app');
```

### Import/Export

**`bundle.stash_to_json(stash_id)`** - Export stash as JSON
```sql
select bundle.stash_to_json('a1b2c3d4-...'::uuid);
```

**`bundle.stash_from_json(json)`** - Import stash from JSON
```sql
select bundle.stash_from_json('{"version":1,"type":"bundle.stash",...}'::jsonb);
```

## Conflict Detection

When applying a stash, if the same field has been modified since the stash was created AND the values differ, you'll get a conflict error:

```
ERROR: Stash conflicts with uncommitted changes: widget.widget.js. Use force=true to overwrite.
```

**Options:**
1. Manually resolve the conflict
2. Use `force` to overwrite current changes:
```sql
select bundle.stash_apply('my-bundle', null, true);  -- force=true
select bundle.stash_pop('my-bundle', true);          -- force=true
```

**No conflict if values match** - If your current changes happen to be identical to what's in the stash, no conflict is raised.

## What Gets Stashed

| Change Type | Stashed | Restored |
|-------------|---------|----------|
| Field edits (offstage) | ✓ Values saved | ✓ Values restored |
| Newly tracked rows | ✓ Row IDs saved | ✓ Re-tracked |
| Staged field changes | ✓ References saved | ✗ Not re-staged |
| Staged row adds/removes | ✓ References saved | ✗ Not re-staged |
| Deleted rows | ✓ References saved | ✗ Not re-deleted |

The common use case (editing widget code, CSS, etc.) is fully supported. Staged state comes back as offstage changes.

## Stash Locality

Stashes are **local to your database** - they are not included in bundle exports. Use `stash_to_json()` to manually transfer stashes between databases.

## UI

The IDE provides a stash panel with:
- List of stashes with timestamps and change counts
- Apply / Pop / Drop buttons
- Copy as JSON button
- New Stash dialog with row selector

## See Also

- [Stash Architecture](design/2026-01-08-stash-architecture.md) - Design decisions and implementation details
