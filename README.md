pg_delta - Version Control for PostgreSQL
=========================================

This is a SQL-only extension for PostgreSQL that provides version control for
data and schema in PostgreSQL.  It version-controls data similarly to how `git`
version-controls files.  For schema, it builds on the [meta]() extension, a
simplified, writible system catalog for PostgreSQL, which makes the Document
Definition Language (DDL) accessible through the Document Manipulation Language
(DML), and thus, version-controls both data and schema in roughly the same way.

Features:

- track, stage and commit
- checkout commits
- branching and merging
- push and pull to/from other databases
