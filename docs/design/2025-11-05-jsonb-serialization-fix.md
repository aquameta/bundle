# JSONB Serialization Fix - 2025-11-05

## Problem

After commits, the `jsonb_fields` column in `bundle.commit` was always empty (`{}`). When attempting to checkout rows with JSONB domain columns (like `meta.function_id`), the operation failed with:

```
ERROR: value for domain meta.function_id violates check constraint "function_id_check"
```

## Root Cause

The `row_to_jsonb_hash_obj()` function in `hash.sql` was using `::text` casting to serialize column values:

```sql
execute format('select ($1).%I::text', col)
```

For JSONB columns, this caused double-escaping. A JSONB value like `{"name": "foo"}` was being serialized as the escaped string `"{\"name\": \"foo\"}"`, which when parsed back as JSON would fail domain constraint checks.

## Solution

Changed to use `to_jsonb()` for proper serialization without escaping:

```sql
execute format('select to_jsonb(($1).%I)::text', col)
```

### Why This Works

The `to_jsonb()` function properly serializes all PostgreSQL types to JSON format:
- Text values become JSON strings with quotes
- Numbers remain as JSON numbers
- JSONB/JSON values are preserved as proper JSON objects/arrays
- NULL becomes JSON null

This eliminates double-escaping and ensures all values are valid JSON that can be parsed back correctly.

## Files Modified

### `/home/eric/dev/aquameta/0.6/core/bundle/hash.sql`

Line 151 - Changed serialization method:
```sql
-- Before:
execute format('select ($1).%I::text', col)

-- After:
execute format('select to_jsonb(($1).%I)::text', col)
```

Also fixed variable shadowing (lines 123-127) - removed duplicate `columns` declaration that was shadowing the function parameter.

### `/home/eric/dev/aquameta/0.6/core/bundle/checkout.sql`

Lines 146-168 - Simplified checkout to parse all values as JSON:
```sql
-- All values are now properly JSON-serialized
for field_key, field_value in select key, value from jsonb_each_text(fields) loop
    unhashed_value := bundle.unhash(field_value);
    -- Parse JSON to get properly typed value
    unhashed_fields := unhashed_fields || jsonb_build_object(field_key, unhashed_value::jsonb);
end loop;
```

Also fixed variable naming ambiguity - changed `schema_name`/`table_name` to `target_schema`/`target_table` to avoid conflicts with `information_schema.columns` column names.

## Benefits

1. **No Double-Escaping** - JSONB columns maintain proper JSON structure
2. **Type Safety** - Domain constraints validate correctly
3. **Consistency** - All PostgreSQL types properly serialized to JSON
4. **Simpler Checkout** - No need for type detection, all values are valid JSON

## Related Issues

This fix also addressed:
- Primary key column ordering in `trackable_relation` view (added `ORDER BY c.position`)
- `_pk_stmt` template in `__commit_stage_fields` function (proper JSONB array indexing)

## Testing

Verified that:
1. Commits now populate `jsonb_fields` correctly
2. Checkout works with JSONB domain columns
3. All PostgreSQL types serialize and deserialize properly
