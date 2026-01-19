# type-identity-search-path

## brief

PostgreSQL type names are not stable - they vary based on search_path, aliases, and schema qualification. This affects function signatures and spec/observed comparison.

## summary

- Type names from pg_catalog change based on current search_path
- `integer` vs `int4` vs `pg_catalog.int4` are the same type, different names
- Custom types like `meta.row_id` may appear with or without schema prefix
- Spec/observed comparison must handle type name normalization
- Consider always schema-qualifying custom types in spec tables
- Built-in types have canonical forms (use regtype cast for normalization)

## full

### The Problem

PostgreSQL's system catalog doesn't store static type names - it stores OIDs. When you query type information, PostgreSQL renders names based on the current `search_path`.

```sql
-- With search_path = 'meta, public, pg_catalog'
SELECT 'meta.row_id'::regtype;  -- returns: row_id

-- With search_path = 'public, pg_catalog'
SELECT 'meta.row_id'::regtype;  -- returns: meta.row_id
```

This means the same function can have different type signatures depending on when/how you query it.

### Type Name Variations

Built-in types have aliases:
- `integer` = `int4` = `pg_catalog.int4`
- `character varying` = `varchar` = `pg_catalog.varchar`
- `boolean` = `bool` = `pg_catalog.bool`

Custom types depend on search_path:
- `meta.row_id` vs `row_id`
- `bundle.version` vs `version`

Array types:
- `integer[]` = `int4[]` = `pg_catalog.int4[]`

### Impact on Spec/Observed

When comparing function specs to observed functions:

```sql
-- Spec says:
type_sig = '{meta.row_id, text}'

-- Observed (with meta in search_path) says:
type_sig = '{row_id, text}'

-- These are THE SAME FUNCTION but won't match!
```

This causes false drift detection.

### Normalization Strategies

**Option 1: Always schema-qualify in spec**
Store fully-qualified names: `{pg_catalog.int4, meta.row_id}`
- Pro: Unambiguous, stable
- Con: Verbose, doesn't match what users write

**Option 2: Use regtype for canonical form**
```sql
SELECT typname::regtype::text FROM pg_type WHERE oid = 'integer'::regtype;
-- Returns: integer (the canonical form)
```
- Pro: PostgreSQL's preferred name
- Con: Still search_path dependent for custom types

**Option 3: Store OIDs, render on demand**
Store type OIDs instead of names, render based on context
- Pro: Truly stable
- Con: OIDs aren't portable across databases

**Option 4: Normalize on comparison**
When comparing spec to observed, normalize both sides:
```sql
-- Pseudo-code
WHERE normalize_type(spec.type) = normalize_type(observed.type)
```
- Pro: Flexible, handles variations
- Con: Complex, potential edge cases

### Current Approach

The function_spec table stores type names as-is from the author or import. The `_canonical_function()` comparison should normalize types before comparing.

TODO: Implement type normalization in canonical comparison.

### Recommendations

1. **For custom types**: Always schema-qualify in spec (`meta.row_id` not `row_id`)
2. **For built-in types**: Use common forms (`integer` not `int4`)
3. **For comparison**: Normalize via regtype cast before comparing
4. **For display**: Show user-friendly names, not internal forms

### Testing Type Equivalence

```sql
-- Check if two type names refer to the same type:
SELECT 'integer'::regtype = 'int4'::regtype;  -- true
SELECT 'meta.row_id'::regtype = 'row_id'::regtype;  -- depends on search_path!
```

### Related Issues

- Function overloading relies on type identity
- The UNIQUE constraint on (schema_name, name, type_sig) must use consistent names
- Import from observed must match the naming convention used in spec
- Bundle checkout must recreate functions with correct types regardless of search_path
