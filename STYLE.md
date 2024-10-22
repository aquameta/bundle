Style Guide
===========

## General
- Lowercase SQL (e.g. `select count(*) from foo`)
- Spaces (4) not tabs
- textwidth = 100

## Error Handling
- Use `raise exception`, not `assert`.  Using `assert` would be nice, but "ASSERT is meant for
  detecting program bugs, not for reporting ordinary error conditions", and can be disabled via
  `plpgsql.check_asserts`.
- Whe possible, use a `begin ... exceptions` block to catch and re-raise exceptions, instead of
  checking for things that constraints already enforce, for much speed.

## Relations
- Singular names
- Lowercase
- Underscores

## Functions
- Use plural names for set-returning functions.
- Functions should start with the action being taken, e.g. `create_repository()`
  instead of `repository_create()`.
- Functions that just return information and don't change state should start with `_get_...`.
- Functions that return a boolean typically start with `_is_...`.
- "public" functions (ones the user might call from the psql prompt or their code) typically take
  human-readable text arguments, e.g. repository name instead of repository id.
- "private" functions begin with a underscore, and typically take ids where applicable.
- Prefer `returns setof` to `returns table`, setof is inlinable where table is not?
- `create or replace function foo( x int, y int, z decimal ) returns x as $$`
- When arguments collide with column names (e.g. `repository_id`), prefix the argument with a
  underscore (e.g. `_repository_id`)

## File Structure
- Each "section" of the project is broken out into it's own file. Drawing clean section lines is
  hard because the project is deeply intertwingled.  Do your best.
- Tests for each section are in `test/$section.sql`, and generally cover basic unit tests like
  calling every function.  Each test file runs it's own pgtap plan (TODO), not complex stories that
  span multiple sections
- The `test/set-counters.sql` script the place for complex, multi-section stories
