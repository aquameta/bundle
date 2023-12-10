------------------------------------------------------------------------------
-- IGNORE RULES
------------------------------------------------------------------------------

-- schema
create table ignored_schema (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_id meta.schema_id not null
);

-- relation
create table ignored_table (
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null
);

-- row
create table ignored_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    row_id meta.row_id
);

-- column
create table ignored_column (
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta.column_id not null
);

-- ignore self
/*
do $$
    for r in select * from meta.table where schema_name = 'delta' -- FIXME
    loop
        -- ignore all internal tables, except for ignore rules, which are version-controlled.
        if r.name not like 'ignored_%' then
            insert into ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
        end if;

        -- attach write-blocking triggers
        -- alternately, could we do this with permissions??  whoa.

    end loop;
end;
$$ language plpgsql;
*/
