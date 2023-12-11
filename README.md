pg_delta - Version Control for PostgreSQL
=========================================

This is a SQL-only extension for PostgreSQL that provides version control for data and schema in
PostgreSQL.  The repository is stored inside the database, and actions are implemented as PostgreSQL
views and functions.  For schema, it builds on the [meta](https://github.com/aquameta/meta)
extension, which makes the Data Definition Language (DDL) accessible through the Data Manipulation
Language (DML), and thus, version-controls both data and schema in roughly the same way.

Features:

- selective tracking of schemas, tables, columns and views
- stage and commit rows and fields
- checkout commits
- schema migrations
- branching and merging
- push and pull to/from other databases
- file system import/export
