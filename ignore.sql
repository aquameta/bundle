------------------------------------------------------------------------------
-- IGNORE RULES
------------------------------------------------------------------------------

-- schema
create table ignored_schema (
    id uuid not null default public.uuid_generate_v7() primary key,
    schema_id meta.schema_id not null
);

-- relation
create table ignored_table (
    id uuid not null default public.uuid_generate_v7() primary key,
    relation_id meta.relation_id not null
);

-- row
create table ignored_row (
    id uuid not null default public.uuid_generate_v7() primary key,
    row_id meta.row_id
);

-- column
create table ignored_column (
    id uuid not null default public.uuid_generate_v7() primary key,
    column_id meta.column_id not null
);
