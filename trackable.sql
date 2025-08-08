------------------------------------------------------------------------------
-- TRACKABLE / IGNORE
------------------------------------------------------------------------------

--
-- trackable_nontable_relation
--

/* By default, only rows in *tables* are included in untracked rows, rows in
 * views and other non-table relations are not.  However, there are times when
 * one might wish to version control views, foreign tables, or other types of
 * non-table relations.  When their relation_id is added to this table, their
 * contents are included in untracked_rows, and can be version-controlled.
 */

create table trackable_nontable_relation(
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null unique,
    pk_column_names text[] not null
);

--
-- [un]track_nontable_relation()
--

create or replace function _track_nontable_relation(_relation_id meta.relation_id, _pk_column_names text[]) returns void as $$
    insert into bundle.trackable_nontable_relation (relation_id, pk_column_names) values (_relation_id, _pk_column_names);
$$ language sql;

create or replace function _untrack_nontable_relation(_relation_id meta.relation_id) returns void as $$
    delete from bundle.trackable_nontable_relation where _relation_id = relation_id;
$$ language sql;


--
-- ignore rules
--

-- schema
create table ignored_schema (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_id meta.schema_id not null
);

-- table
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
-- ignore_*() functions
--

-- schema
create or replace function ignore_schema( _schema_id meta.schema_id ) returns void as $$
    insert into bundle.ignored_schema(schema_id) values (_schema_id);
$$ language sql;

create or replace function unignore_schema( _schema_id meta.schema_id ) returns void as $$
    delete from bundle.ignored_schema where schema_id = _schema_id;
$$ language sql;


-- table
create or replace function ignore_table( _relation_id meta.relation_id ) returns void as $$
    insert into bundle.ignored_table(relation_id) values (_relation_id);
$$ language sql;

create or replace function unignore_table( _relation_id meta.relation_id ) returns void as $$
    delete from bundle.ignored_table where relation_id = _relation_id;
$$ language sql;


-- row
create or replace function ignore_row( _row_id meta.row_id ) returns void as $$
    insert into bundle.ignored_row(row_id) values (_row_id);
$$ language sql;

create or replace function unignore_row( _row_id meta.row_id ) returns void as $$
    delete from bundle.ignored_row where row_id = _row_id;
$$ language sql;


-- column
create or replace function ignore_column( _column_id meta.column_id ) returns void as $$
    insert into bundle.ignored_column(column_id) values (_column_id);
$$ language sql;

create or replace function unignore_column( _column_id meta.column_id ) returns void as $$
    delete from bundle.ignored_column where column_id = _column_id;
$$ language sql;


--
-- tracked query
--

create table tracked_query(
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id),
    query text,
    pk_column_names text[] not null
);


--
-- trackable relation
--

create or replace view trackable_relation as
    select relation_id, primary_key_column_names as pk_column_names
    from (
        -- every table that has a primary key
        select
            t.id as relation_id,
            r.primary_key_column_names
        from meta.schema s
            join meta.table t on t.schema_id=s.id
            join meta.relation r on r.id=t.id
        -- only work with relations that have a primary key
        where primary_key_column_ids is not null and primary_key_column_ids != '{}'

        -- ...plus every trackable_nontable_relation
        union

        select
            relation_id,
            pk_column_names
        from bundle.trackable_nontable_relation
    ) r

    -- ...that is not ignored

    where relation_id not in (
        select relation_id from bundle.ignored_table
    )

    -- ...and is not in an ignored schema

        and relation_id::meta.schema_id not in (
            select schema_id from bundle.ignored_schema
        )
    ;


--
-- not_ignored_row_stmt
--

create or replace view not_ignored_row_stmt as
select *, 'select meta.make_row_id(' ||
        quote_literal(r.relation_id->>'schema_name') || ', ' ||
        quote_literal(r.relation_id->>'name') || ', ' ||
        quote_literal(r.pk_column_names) || '::text[], ' ||
        'array[' ||
            meta._pk_stmt(r.pk_column_names, null, '%1$I::text', ',') ||
        ']' ||
    ') as row_id from ' ||
    quote_ident(r.relation_id->>'schema_name') || '.' || quote_ident(r.relation_id->>'name') ||

    -- special case meta rows so that ignored_* cascades down to all objects in its scope:
    -- exclude rows from meta that are in "normal" tables that are ignored
    case
        -- schemas
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' = 'schema' then
           ' where id not in (select schema_id from bundle.ignored_schema) '
        -- relations
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' in ('table', 'view', 'relation') then
           ' where id not in (select relation_id from bundle.ignored_table) and schema_id not in (select schema_id from bundle.ignored_schema)'
        -- functions
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' = 'function' then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- columns
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' = 'column' then
           ' where id not in (select column_id from bundle.ignored_column) and id::meta.relation_id not in (select relation_id from bundle.ignored_table) and id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'

        -- objects that exist in schema scope

        -- operator
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' in ('operator') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema)'
        -- type
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' in ('type') then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- constraint_unique, constraint_check, table_privilege
        when r.relation_id->>'schema_name' = 'meta' and r.relation_id->>'name' in ('constraint_check','constraint_unique','table_privilege') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema) and table_id not in (select relation_id from bundle.ignored_table)'
        else ''
    end

    -- TODO: When meta views are tracked via 'trackable_nontable_relation', they should exclude
    -- rows from meta that are in trackable non-table tables that are ignored

    as stmt
from bundle.trackable_relation r;



--
-- get_untracked_rows()
--

create or replace function _get_untracked_rows(_relation_id meta.relation_id default null) returns setof meta.row_id as $$
-- all rows that aren't ignored by an ignore rule
select r.row_id
from bundle.exec((
    select array_agg (stmt)
    from bundle.not_ignored_row_stmt
    where relation_id = coalesce(_relation_id, relation_id)
)) r (row_id meta.row_id)

except

-- ...except the following:
select * from (
    -- stage_rows_to_add
    select jsonb_array_elements_text(r.stage_rows_to_add)::meta.row_id from bundle.repository r -- where relation_id=....?

    union
    -- tracked rows
    -- select t.row_id from bundle.track_untracked_rowed t
    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id from bundle.repository r -- where relation_id=....?

    union
    -- stage_rows_to_remove
    -- select d.row_id from bundle.stage_row_to_remove
    select jsonb_array_elements_text(r.stage_rows_to_remove)::meta.row_id from bundle.repository r-- where relation_id=....?

    union
    -- head_commit_rows for all tables
    select hcr.row_id as row_id
    from bundle.repository r, bundle._get_head_commit_rows(r.id) hcr
) r;
$$ language sql;


--
-- _get_trackable_relation_pk()
--

-- returns the pk_column_name(s) of a relation's primary key, including of nontable_relations

create or replace function _get_trackable_relation_pk(_relation_id meta.relation_id)
returns text[] as $$
declare
    pk_column_names text[];
begin
    -- first check trackable_relations view, to catch nontable_relations (and anything else)
    select tr.pk_column_names from bundle.trackable_relation tr where relation_id = _relation_id into pk_column_names;

    if pk_column_names is not null and array_length(pk_column_names, 1) is not null then
        return pk_column_names;
    end if;


    select array_agg(a.attname order by array_position(c.conkey, a.attnum))
    into pk_column_names
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    join pg_attribute a on a.attnum = any(c.conkey) and a.attrelid = t.oid
    where n.nspname = (_relation_id).schema_name
      and t.relname = (_relation_id).name
      and c.contype = 'p';

    if pk_column_names is null then
        raise exception 'No primary key found for table %.%', schema_name, table_name;
    end if;

    return pk_column_names;
end;
$$ language plpgsql;
