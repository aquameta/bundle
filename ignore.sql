------------------------------------------------------------------------------
-- TRACKABLE / IGNORE
------------------------------------------------------------------------------

----------------------------------
-- ignore rules
----------------------------------

-- schema
create table ignored_schema (
    id uuid not null default public.uuid_generate_v7() primary key,
    schema_id meta.schema_id not null
);

-- table
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

----------------------------------
-- functions
----------------------------------

-- schema
create or replace function ignore_schema( _schema_id meta.schema_id ) returns void as $$
    insert into delta.ignored_schema(schema_id) values (_schema_id);
$$ language sql;

create or replace function unignore_schema( _schema_id meta.schema_id ) returns void as $$
    delete from delta.ignored_schema where schema_id = _schema_id;
$$ language sql;


-- table
create or replace function ignore_table( _relation_id meta.relation_id ) returns void as $$
    insert into delta.ignored_table(relation_id) values (_relation_id);
$$ language sql;

create or replace function unignore_table( _relation_id meta.relation_id ) returns void as $$
    delete from delta.ignored_table where relation_id = _relation_id;
$$ language sql;


-- row
create or replace function ignore_row( _row_id meta.row_id ) returns void as $$
    insert into delta.ignored_row(row_id) values (_row_id);
$$ language sql;

create or replace function unignore_row( _row_id meta.row_id ) returns void as $$
    delete from delta.ignored_row where row_id = _row_id;
$$ language sql;



-- column
create or replace function ignore_column( _column_id meta.column_id ) returns void as $$
    insert into delta.ignored_column(column_id) values (_column_id);
$$ language sql;

create or replace function unignore_column( _column_id meta.column_id ) returns void as $$
    delete from delta.ignored_column where column_id = _column_id;
$$ language sql;
