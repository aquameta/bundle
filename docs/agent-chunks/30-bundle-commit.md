# bundle-commit

## brief

Commits create immutable snapshots of staged changes. A commit contains rows to add, rows to remove, and fields to change. Use `checkout()` to apply a commit's state to the database.

## summary

- `bundle.commit('name', 'message', 'author', 'email')` - create commit from staged changes
- `bundle.checkout('name')` - apply HEAD commit to database
- `bundle.delete_checkout('name')` - remove checked-out rows from database
- `bundle.get_head_commit_rows('name')` - list rows in HEAD commit
- `bundle.head_commit_id('name')` - get HEAD commit UUID
- `bundle.commit_log('name')` - view commit history

## full

### Creating a Commit

Commits all staged changes (rows to add, rows to remove, fields to change):

```sql
select bundle.commit(
    'org.aquameta.ui.ide',
    'Add new widget for row creation',
    'Your Name',
    'you@example.com'
);
-- Returns: uuid of new commit
```

Optional parent commit (defaults to HEAD):
```sql
select bundle.commit(
    'org.aquameta.ui.ide',
    'message',
    'author',
    'email',
    'parent-commit-uuid'::uuid
);
```

### Commit Data Structure

The `bundle.commit` table stores:
- `id` - Commit UUID
- `repository_id` - Which repository
- `parent_id` - Previous commit (NULL for first commit)
- `message`, `author_name`, `author_email`, `commit_time`
- `jsonb_rows` - Array of row_ids in this commit
- `jsonb_fields` - Object mapping row_id → {column: value_hash}

### Viewing Commits

```sql
-- Get HEAD commit UUID
select bundle.head_commit_id('org.aquameta.ui.ide');

-- Get checkout commit UUID
select bundle.checkout_commit_id('org.aquameta.ui.ide');

-- View commit history
select * from bundle.commit_log('org.aquameta.ui.ide');

-- List rows in HEAD commit
select * from bundle.get_head_commit_rows('org.aquameta.ui.ide');

-- Filter by relation
select * from bundle.get_head_commit_rows(
    'org.aquameta.ui.ide',
    meta.make_relation_id('widget', 'widget')
);
```

### Checkout

Apply a commit's state to the database:

```sql
-- Checkout HEAD commit
select bundle.checkout('org.aquameta.ui.ide');

-- Checkout with upsert (update existing rows instead of failing)
select bundle.checkout('org.aquameta.ui.ide', true);

-- Remove checked-out rows from database
select bundle.delete_checkout('org.aquameta.ui.ide');
```

### Historical Data

```sql
-- Get field value at a specific commit
select bundle.get_field_at_commit(commit_id, field_id);

-- Get row at a specific commit
select bundle.get_row_at_commit(commit_id, row_id);

-- Get all rows at a specific commit
select * from bundle.get_rows_at_commit(commit_id);
```

### Typical Full Workflow

```sql
-- 1. Make changes to database (insert, update, delete rows)

-- 2. Track new rows
select bundle.track_untracked_row('my.bundle', row_id);

-- 3. Stage everything
select bundle.stage_tracked_rows('my.bundle');
select bundle.stage_updated_fields('my.bundle');
select bundle.stage_deleted_rows('my.bundle');

-- 4. Check status
select bundle.status('my.bundle');

-- 5. Commit
select bundle.commit('my.bundle', 'message', 'author', 'email');
```
