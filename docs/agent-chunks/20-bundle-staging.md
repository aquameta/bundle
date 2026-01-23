# bundle-staging

## brief

Staging prepares changes for commit. Stage new rows, field changes, and deletions separately. The stage is stored in repository columns: `stage_rows_to_add`, `stage_rows_to_remove`, `stage_fields_to_change`.

## summary

- `bundle.stage_all('name')` - stage everything: tracked rows, field changes, and deleted rows
- `bundle.stage_tracked_row('name', row_id)` - stage one tracked row
- `bundle.stage_tracked_rows('name')` - stage all tracked rows
- `bundle.stage_updated_fields('name')` - stage all field changes
- `bundle.stage_deleted_rows('name')` - stage all deleted rows for removal
- `bundle.stage_row_to_remove('name', row_id)` - stage one row for deletion
- `bundle.empty_stage('name')` - clear all staged changes
- `bundle.unstage_*` functions to undo staging

## full

### Three Types of Staged Changes

1. **Rows to add** - New rows being added to the repository
2. **Rows to remove** - Existing rows being deleted from the repository
3. **Fields to change** - Modified field values on existing rows

### Staging New Rows

Tracked rows must be staged before commit:

```sql
-- Stage a single tracked row
select bundle.stage_tracked_row(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);

-- Stage ALL tracked rows at once
select bundle.stage_tracked_rows('org.aquameta.ui.ide');
```

### Staging Field Changes

When you modify fields on already-committed rows:

```sql
-- Stage all changed fields
select bundle.stage_updated_fields('org.aquameta.ui.ide');

-- Stage changes only in a specific table
select bundle.stage_updated_fields(
    'org.aquameta.ui.ide',
    meta.make_relation_id('widget', 'widget')
);
```

### Staging Deletions

When rows have been deleted from the database:

```sql
-- Stage all deleted rows for removal
select bundle.stage_deleted_rows('org.aquameta.ui.ide');

-- Stage a specific row for removal
select bundle.stage_row_to_remove(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);
```

### Viewing Staged Changes

```sql
-- Views for staged changes
select * from bundle.stage_row_to_add;
select * from bundle.stage_row_to_remove;
select * from bundle.stage_field_to_change;
```

### Unstaging

Undo staging operations:

```sql
-- Unstage a row (moves back to tracked)
select bundle.unstage_tracked_row('org.aquameta.ui.ide', row_id);

-- Unstage a field change
select bundle.unstage_field_to_change('org.aquameta.ui.ide', field_id);

-- Unstage a row removal
select bundle.unstage_row_to_remove('org.aquameta.ui.ide', row_id);

-- Clear entire stage
select bundle.empty_stage('org.aquameta.ui.ide');

-- Unstage everything (moves staged rows back to tracked)
select bundle.unstage_all('org.aquameta.ui.ide');
```

### Staging Everything at Once

Use `stage_all()` to stage tracked rows, field changes, and deleted rows in one call:

```sql
-- Stage all changes at once
select bundle.stage_all('org.aquameta.ui.ide');

-- With optional relation filter
select bundle.stage_all(
    'org.aquameta.ui.ide',
    meta.make_relation_id('widget', 'widget')
);
```

### Typical Workflow

```sql
-- After making changes to widgets...

-- Option A: Stage everything at once
select bundle.stage_all('org.aquameta.ui.ide');

-- Option B: Stage separately for more control
-- 1. Stage any new tracked rows
select bundle.stage_tracked_rows('org.aquameta.ui.ide');
-- 2. Stage field changes (edits to existing rows)
select bundle.stage_updated_fields('org.aquameta.ui.ide');
-- 3. Stage deletions (if any rows were deleted)
select bundle.stage_deleted_rows('org.aquameta.ui.ide');

-- Check status
select bundle.status('org.aquameta.ui.ide');

-- Commit
select bundle.commit('org.aquameta.ui.ide', 'message', 'author', 'email');
```
