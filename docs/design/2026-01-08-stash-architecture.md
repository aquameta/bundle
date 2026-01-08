# Bundle Stash Architecture

**Summary:** Git-stash-like functionality for saving and restoring uncommitted database changes.

## User Goals

> "I want to save my uncommitted changes temporarily, switch to something else, then restore them later."

> "If I'm about to overwrite uncommitted work, warn me first."

## Core Concept

Stash captures the current state of uncommitted changes (both staged and offstage), reverts to the committed state via checkout, and stores the captured state for later restoration.

```
┌─────────────────────────────────────────────────────────────┐
│                    Uncommitted Changes                       │
├─────────────────────────────────────────────────────────────┤
│  STAGED                    │  OFFSTAGE                      │
│  - rows_to_add             │  - tracked_rows_added          │
│  - rows_to_remove          │  - deleted_rows                │
│  - fields_to_change        │  - updated_fields (with values)│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ stash()
┌─────────────────────────────────────────────────────────────┐
│                      bundle.stash                            │
│  - Captures all above state                                  │
│  - Stores actual field VALUES (not just references)          │
│  - Calls checkout() to restore committed state               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ pop() / apply()
┌─────────────────────────────────────────────────────────────┐
│                    Restored State                            │
│  - Field values written back to database                     │
│  - Newly tracked rows re-tracked                             │
│  - (Staged state NOT restored - comes back as offstage)      │
└─────────────────────────────────────────────────────────────┘
```

## Data Model

```sql
create type bundle.stash_field_value as (
    field_id meta.field_id,
    value text                    -- Actual value at stash time
);

create table bundle.stash (
    id uuid primary key,
    repository_id uuid references bundle.repository(id),
    message text,
    created_at timestamptz,

    -- Staged state (references only)
    stage_rows_to_add meta.row_id[],
    stage_rows_to_remove meta.row_id[],
    stage_fields_to_change meta.field_id[],

    -- Offstage state
    offstage_tracked_rows_added meta.row_id[],
    offstage_deleted_rows meta.row_id[],
    offstage_updated_fields bundle.stash_field_value[]  -- With values!
);
```

## Key Design Decisions

### 1. Value Storage for Field Changes

Stash stores the actual text value of each changed field, not just references. This enables:
- Restoration after checkout has reset the database
- Conflict detection by comparing values
- Portable JSON export/import

### 2. Conflict Detection with Value Comparison

When applying a stash, we check if restoring would overwrite different uncommitted changes:

```sql
-- Conflict only if:
-- 1. Field is in stash AND currently uncommitted
-- 2. Current value differs from stash value
if exists (select from _get_offstage_updated_fields where field_id = stash_field_id)
   and current_value is distinct from stash_value then
    -- CONFLICT
end if;
```

If values are identical, no conflict - the stash would write the same value anyway.

### 3. Force Option

Both `stash_apply()` and `stash_pop()` accept `_force boolean`:
- `false` (default): Fail with error listing conflicting fields
- `true`: Overwrite current values with stash values

### 4. What Gets Restored vs What Doesn't

**Restored on pop/apply:**
- `offstage_updated_fields` → Values written back to database
- `offstage_tracked_rows_added` → Rows re-tracked (if still exist)

**NOT restored:**
- `stage_rows_to_add/remove` → Staging area not restored
- `stage_fields_to_change` → Staging area not restored
- `offstage_deleted_rows` → Rows not re-deleted

**Rationale:** Staged state is transient intent. After checkout clears everything, restoring "staged for removal" is ambiguous. The common use case is field edits, which we handle fully.

### 5. Selective Stashing

`stash_rows()` allows stashing only specific rows:
- Filters all arrays to only include specified row_ids
- Does NOT auto-revert (checkout would affect all rows)
- User can manually revert specific rows if needed

### 6. Stash Locality

Stashes are **local only** - not exported with bundles:
- Similar to git stash (not pushed to remotes)
- Repository-specific (tied to repository_id)
- JSON export/import available for manual transfer

## API

### Core Operations

```sql
-- Stash all uncommitted changes
bundle.stash(repository_name, message) → uuid

-- Stash specific rows only
bundle.stash_rows(repository_name, row_ids jsonb, message) → uuid

-- Apply most recent or specific stash (keep stash)
bundle.stash_apply(repository_name, stash_id, force) → uuid

-- Pop most recent stash (apply + delete)
bundle.stash_pop(repository_name, force) → uuid

-- Delete stash without applying
bundle.stash_drop(stash_id) → void

-- List stashes
bundle.stash_list(repository_name) → table

-- Show stash contents
bundle.stash_show(stash_id) → table
```

### Utility Operations

```sql
-- Export stash to portable JSON
bundle.stash_to_json(stash_id) → jsonb

-- Import stash from JSON
bundle.stash_from_json(json) → uuid

-- Get all uncommitted changes (for UI row selector)
bundle.uncommitted_changes(repository_name) → table
```

## UI Integration

The stash widget (`ide-bundle-stash`) provides:
- List of stashes with metadata
- Actions: Apply, Pop, Drop, Copy (JSON)
- New Stash dialog with:
  - "All changes" vs "Selected rows" mode
  - Row selector with checkboxes
  - Message input
- Conflict handling:
  - Shows error with conflicting fields
  - Offers force option via confirm dialog

## PostgreSQL Implementation Notes

### Composite Type Field Access

When accessing fields from composite types in PL/pgSQL SQL queries, operator precedence requires parentheses:

```sql
-- WRONG - fails with "operator does not exist: text ->> unknown"
(_sfv).field_id->>'schema_name' || '.' || (_sfv).field_id->>'relation_name'

-- RIGHT - parentheses around each extraction
((_sfv).field_id->>'schema_name') || '.' || ((_sfv).field_id->>'relation_name')
```

### Domain Type Casting in Dynamic SQL

When using `meta.field_id` (jsonb domain) from composite types in dynamic queries:

```sql
-- For conflict detection query (needs explicit text::jsonb cast)
where ((sfv).field_id)::text::jsonb in (select field_id::jsonb from ...)

-- For foreach loop variable access (works directly)
execute format('...', (_sfv).field_id->>'column_name', ...)
```

## Future Considerations

### Auto-Backup on Force

When force-applying over uncommitted changes, could auto-create a backup stash first:
```sql
-- Before force apply:
-- 1. Create "Auto-backup before force apply" stash
-- 2. Then apply the requested stash
```

### Staged State Restoration

Could restore staged state by re-staging items:
```sql
-- After restoring field values:
perform bundle.stage_row_add(repo, row_id) for each stage_rows_to_add;
perform bundle.stage_field_change(repo, field_id) for each stage_fields_to_change;
```

### Deleted Row Restoration

Could re-delete rows that were deleted before stash:
```sql
-- After checkout restores rows:
delete from schema.table where pk = value for each offstage_deleted_rows;
```

Both are potentially dangerous and would need careful UX consideration.
