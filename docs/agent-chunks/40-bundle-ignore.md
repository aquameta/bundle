# bundle-ignore

## brief

Ignore rules exclude schemas, tables, rows, or columns from version control. Ignored items won't appear in `_get_untracked_rows()`. Use for ephemeral data, caches, large tables, or sensitive columns.

## summary

- `bundle.ignore_schema(schema_id)` - ignore entire schema
- `bundle.ignore_table(relation_id)` - ignore a table
- `bundle.ignore_row(row_id)` - ignore a specific row
- `bundle.ignore_column(column_id)` - ignore a column (e.g., passwords)
- Corresponding `unignore_*` functions to remove rules
- Stored in: `ignored_schema`, `ignored_table`, `ignored_row`, `ignored_column` tables

## full

### When to Use Ignore Rules

**Ignore schemas** for:
- System schemas (`pg_catalog`, `information_schema`)
- Temporary/test schemas

**Ignore tables** for:
- Session/cache tables
- Large data tables not suitable for VCS
- Audit logs, metrics

**Ignore rows** for:
- Local configuration that shouldn't sync
- Machine-specific settings

**Ignore columns** for:
- Password hashes
- API tokens/secrets
- Personally identifiable information (PII)

### Ignoring

```sql
-- Ignore a schema
select bundle.ignore_schema(meta.make_schema_id('temp_data'));

-- Ignore a table
select bundle.ignore_table(meta.make_relation_id('public', 'session_cache'));

-- Ignore a specific row
select bundle.ignore_row(
    meta.make_row_id('public', 'config', 'key', 'local_machine_id')
);

-- Ignore a column
select bundle.ignore_column(
    meta.make_column_id('public', 'users', 'password_hash')
);
```

### Unignoring

```sql
select bundle.unignore_schema(meta.make_schema_id('temp_data'));
select bundle.unignore_table(meta.make_relation_id('public', 'session_cache'));
select bundle.unignore_row(row_id);
select bundle.unignore_column(column_id);
```

### Viewing Ignore Rules

```sql
-- View all ignore rules
select * from bundle.ignored_schema;
select * from bundle.ignored_table;
select * from bundle.ignored_row;
select * from bundle.ignored_column;
```

### Effect on Tracking

Ignored items are excluded from `_get_untracked_rows()`:

```sql
-- This won't show rows from ignored tables/schemas
select * from bundle._get_untracked_rows();
```

The `bundle.trackable_relation` view only shows relations that:
- Have a primary key
- Are not in an ignored schema
- Are not explicitly ignored
