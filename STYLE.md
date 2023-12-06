Style Guide
===========

## General
- Lowercase SQL (e.g. `select count(*) from foo`)
- textwidth = 100

## Error Handling
- Use `raise exception`, not `assert`.  Using `assert` would be nice, but "ASSERT is meant for
  detecting program bugs, not for reporting ordinary error conditions", and can be disabled via
  `plpgsql.check_asserts`.

## Functions
- "public" functions (ones the user might call from the psql prompt or their code) typically take
  human-readable text arguments, e.g. repository name instead of repository id
- "private" functions begin with a underscore, and typically take ids where applicable
- `create or replace function foo( x int, y int, z decimal ) returns x as $$`
- When arguments collide with column names (e.g. `repository_id`), prefix the argument with a
  underscore (e.g. `_repository_id`)
