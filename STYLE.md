Style Guide
===========

## general
- lowercase sql
- set textwidth=100


## functions
- "public" functions (ones the user might call from the psql prompt or their code) typically take
  human-readable text arguments, e.g. repository name instead of repository id
- "private" functions with a underscore, and typically take ids where applicable
- `create or replace function foo( x int, y int, z decimal ) returns x as $$`
- when arguments collide with column names (e.g. `repository_id`), prefix the argument with a
  underscore (e.g. `_repository_id`)

