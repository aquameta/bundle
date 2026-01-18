------------------------------------------------------------------------------
-- TYPES
-- All custom type definitions for the bundle module
------------------------------------------------------------------------------

--
-- Version Domain
-- Semantic versioning 2.0.0 with validation
--

create domain bundle.version as text
    check (
        value ~
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' -- x.y.z
        '(-([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?'              -- -prerelease
        '(\+([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$'            -- +build
    );


--
-- Repository & Commit Types
--

-- Field identifier with hash value
create type field_hash as ( field_id meta.field_id, value_hash text);

-- Row identifier with existence flag
create type row_exists as( row_id meta.row_id, exists boolean );

-- Commit ancestry information
create type _commit_ancestor as(
    commit_id uuid,
    position integer,
    commit_time timestamptz,
    message text,
    author_name text,
    author_email text
);

-- Schema relationship edge (for dependency tracking)
create type bundle.schema_edge as (from_relation_id meta.relation_id, to_relation_id meta.relation_id);


--
-- Stage Types
--

-- Field hash difference (for tracking changes)
create type field_hash_diff as (
    field_id meta.field_id,
    db_value_hash text,
    commit_value_hash text
);

-- Stage row with new row flag
create type stage_row as (row_id meta.row_id, new_row boolean);


--
-- Stash Types
--

-- Field value for stash storage
create type bundle.stash_field_value as (
    field_id meta.field_id,
    value text
);


--
-- Status Types
--

-- Row state enumeration
create type row_state as enum ('tracked', 'staged', 'in_commit');
