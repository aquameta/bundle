# bundle-basics

## brief

Bundle is git-like version control for database rows. Three atomic operations: rows created, rows deleted, fields changed. Functions with `_` prefix take UUIDs, without prefix take repository names.

## summary

- **Three operations**: row create, row delete, field change - that's all commits track
- `bundle.create_repository('name')` - create new repository
- `bundle.track_untracked_row('name', row_id)` - add row to tracking
- `bundle.stage_tracked_row('name', row_id)` - stage for commit
- `bundle.commit('name', 'message', 'author', 'email')` - create commit
- Functions: `function('name')` convenience wrappers, `_function(uuid)` direct access
- See `core/meta/AGENTS.md` for meta identifier types (row_id, relation_id, field_id)

## full

### Core Philosophy

There are only three things that ever happen in a database:
1. **Rows are created**
2. **Rows are deleted**
3. **Fields are changed**

A commit is a "delta" composed of these three atomic operations.

### Essential Workflow

```sql
-- 1. Find untracked rows (not in any bundle)
select * from bundle._get_untracked_rows();
select * from bundle._get_untracked_rows(meta.make_relation_id('widget', 'widget'));

-- 2. Track a row
select bundle.track_untracked_row(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);

-- 3. Stage the tracked row
select bundle.stage_tracked_row(
    'org.aquameta.ui.ide',
    meta.make_row_id('widget', 'widget', 'id', 'some-uuid')
);

-- 4. Commit
select bundle.commit(
    'org.aquameta.ui.ide',
    'Add new widget',
    'Your Name',
    'you@example.com'
);
```

### Function Naming Convention

Functions come in pairs - name-based wrappers call `repository_id()` internally:

```sql
-- By name (convenience)
select bundle.track_untracked_row('org.aquameta.ui.ide', row_id);

-- By UUID (direct)
select bundle._track_untracked_row(repo_uuid, row_id);
```

### Meta Identifiers

Bundle uses meta module identifier types. Quick reference:

```sql
-- row_id: identifies a specific row
select meta.make_row_id('widget', 'widget', 'id', 'some-uuid');

-- relation_id: identifies a table/view
select meta.make_relation_id('widget', 'widget');
```

See `core/meta/AGENTS.md` for complete documentation.

### Key Functions

```sql
-- Create a new repository
select bundle.create_repository('com.example.myapp');

-- Check status
select bundle.status('org.aquameta.ui.ide');

-- Get repository UUID from name
select bundle.repository_id('org.aquameta.ui.ide');

-- Check if repository exists
select bundle.repository_exists('org.aquameta.ui.ide');
```

### Repository Table Structure

```
bundle.repository
├── id                     uuid (PK)
├── name                   text (unique, not empty)
├── head_commit_id         uuid → commit
├── checkout_commit_id     uuid → commit
├── tracked_rows_added     jsonb[] of row_ids
├── stage_rows_to_add      jsonb[] of row_ids
├── stage_rows_to_remove   jsonb[] of row_ids
└── stage_fields_to_change jsonb[] of field_ids
```

### Useful Views

- `bundle.trackable_relation` - relations that can be tracked (have PKs, not ignored)
- `bundle.tracked_row_added` - newly tracked rows across all repos
- `bundle.stage_row_to_add` - rows staged for addition
