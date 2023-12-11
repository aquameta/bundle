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


--
-- ignore self, system catalogs, internal schemas, public
--

do $$
    declare r record;
    begin
        for r in
            select * from meta.table where schema_name = 'delta' and name not like 'ignored%'
        loop
            -- ignore all internal tables, except for ignore rules, which are version-controlled.
            if r.name not like 'ignored_%' then
                insert into ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
            end if;

        end loop;

        -- ignore system catalogs, pg_temp*, pg_toast*, public (TODO: audit use of public)

        for r in
            select * from meta.schema
                where name in ('pg_catalog','public','information_schema')
                    or name like 'pg_toast%'
                    or name like 'pg_temp%'
        loop
            -- ignore all internal tables, except for ignore rules, which are version-controlled.
            if r.name not like 'ignored_%' then
                insert into ignored_schema(schema_id) values (meta.schema_id(r.name));
            end if;

        end loop;
    end;
$$ language plpgsql;


-- track the above rows
/*
TODO: we can't do this here because track_row() doesn't exist yet.
select delta.repository_create('io.aquadelta.core.repository');
select delta.track_row('io.aquadelta.core.repository', 'delta','ignored_table','id',id::text) from delta.ignored_table;
select delta.track_row('io.aquadelta.core.repository', 'delta','ignored_schema','id',id::text) from delta.ignored_schema;
*/
