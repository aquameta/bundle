------------------------------------------------------------------------------
-- TRACKED / UNTRACKED ROWS
------------------------------------------------------------------------------

/*
 * trackable_nontable_relation
 *
 * By default, only rows in *tables* are included in untracked rows, rows in
 * views and other non-table relations are not.  However, there are times when
 * one might wish to version control views, foreign tables, or other types of
 * non-table relations.  When their relation_id is added to this table, their
 * contents are included in untracked_rows, and can be version-controlled.
 */

create table trackable_nontable_relation(
    id uuid not null default public.uuid_generate_v7() primary key,
    relation_id meta.relation_id not null unique,
    pk_column_names text[] not null
);


/*
 * [un]track_nontable_relation()
 */

create or replace function _track_nontable_relation(_relation_id meta.relation_id, _pk_column_names text[]) returns void as $$
    insert into delta.trackable_nontable_relation (relation_id, pk_column_names) values (_relation_id, _pk_column_names);
$$ language sql;

create or replace function _untrack_nontable_relation(_relation_id meta.relation_id) returns void as $$
    delete from delta.trackable_nontable_relation where _relation_id = relation_id;
$$ language sql;


/*
 * _is_newly_tracked()
 */

create or replace function _is_newly_tracked( repository_id uuid, row_id meta.row_id ) returns boolean as $$
declare
    row_count integer;
begin
    select count(*) into row_count from delta.repository
	where id = repository_id
		and tracked_rows_added ? row_id::text;

    if row_count > 0 then
        return true;
    else
        return false;
    end if;
end;
$$ language plpgsql;


/*
 * track_untracked_row()
 *
 * Adds an untracked row to a repository's tracked_rows_added column.
 */

create or replace function _track_untracked_row( _repository_id uuid, row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        /*
        TODO: cruft from pre-json days, refactor this to check repository.tracked_rows_added
        if meta.row_exists(meta.row_id('delta','tracked_row_added', 'row_id', row_id::text)) then
            raise exception 'Row with row_id % is already tracked.', row_id;
        end if;
        */

        -- assert row exists
        if not meta.row_exists(row_id) then
            raise exception 'Row with row_id % does not exist.', row_id;
        end if;

        -- assert row is not already tracked
        if delta._is_newly_tracked(_repository_id, row_id) then
            raise exception 'Row with row_id % is already tracked.', row_id;
        end if;

        update delta.repository set tracked_rows_added = tracked_rows_added || to_jsonb(row_id::text) where id = _repository_id;
    end;
$$ language plpgsql;


create or replace function track_untracked_row( repository_name text, row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._track_untracked_row(
            delta.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- untrack_tracked_row()
--

create or replace function _untrack_tracked_row( _repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        c integer;
    begin
        
        select count(*) into c from delta.repository where id = _repository_id and tracked_rows_added ? _row_id::text;
        if c < 1 then
            raise exception 'Row with row_id % cannot be removed because it is not tracked by supplied repository.', _row_id::text;
        end if;

        update delta.repository set tracked_rows_added = tracked_rows_added - _row_id::text where id = _repository_id;

        return tracked_row_id;
    end;
$$ language plpgsql;

create or replace function untrack_tracked_row( name text, row_id meta.row_id ) returns uuid as $$
    select delta._untrack_tracked_row(delta.repository_id(name), row_id);
$$ language sql;


--
-- trackable relation
--

create or replace view trackable_relation as
    select relation_id, primary_key_column_names
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
            pk_column_names as primary_key_column_names
        from delta.trackable_nontable_relation
    ) r

    -- ...that is not ignored

    where relation_id not in (
        select relation_id from delta.ignored_table
    )

    -- ...and is not in an ignored schema

        and relation_id::meta.schema_id not in (
            select schema_id from delta.ignored_schema
        )
    ;


--
-- not_ignored_row_stmt
--

create or replace view not_ignored_row_stmt as
select *, 'select meta.row_id(' ||
        quote_literal((r.relation_id).schema_name) || ', ' ||
        quote_literal((r.relation_id).name) || ', ' ||
        quote_literal(r.primary_key_column_names) || '::text[], ' ||
        'array[' ||
            meta._pk_stmt(r.primary_key_column_names, null, '%1$I::text', ',') ||
        ']' ||
    ') as row_id from ' ||
    quote_ident((r.relation_id).schema_name) || '.' || quote_ident((r.relation_id).name) ||

    -- special case meta rows so that ignored_* cascades down to all objects in its scope:
    -- exclude rows from meta that are in "normal" tables that are ignored
    case
        -- schemas
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) = 'schema' then
           ' where id not in (select schema_id from delta.ignored_schema) '
        -- relations
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) in ('table', 'view', 'relation') then
           ' where id not in (select relation_id from delta.ignored_table) and schema_id not in (select schema_id from delta.ignored_schema)'
        -- functions
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) = 'function' then
           ' where id::meta.schema_id not in (select schema_id from delta.ignored_schema)'
        -- columns
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) = 'column' then
           ' where id not in (select column_id from delta.ignored_column) and id::meta.relation_id not in (select relation_id from delta.ignored_table) and id::meta.schema_id not in (select schema_id from delta.ignored_schema)'

        -- objects that exist in schema scope

        -- operator
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) in ('operator') then
           ' where meta.schema_id(schema_name) not in (select schema_id from delta.ignored_schema)'
        -- type
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) in ('type') then
           ' where id::meta.schema_id not in (select schema_id from delta.ignored_schema)'
        -- constraint_unique, constraint_check, table_privilege
        when (r.relation_id).schema_name = 'meta' and ((r.relation_id).name) in ('constraint_check','constraint_unique','table_privilege') then
           ' where meta.schema_id(schema_name) not in (select schema_id from delta.ignored_schema) and table_id not in (select relation_id from delta.ignored_table)'
        else ''
    end

    -- TODO: When meta views are tracked via 'trackable_nontable_relation', they should exclude
    -- rows from meta that are in trackable non-table tables that are ignored

    as stmt
from delta.trackable_relation r;


--
-- tracked_rows_added
--

create or replace function _get_tracked_rows_added( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(tracked_rows_added)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create or replace view tracked_row_added as
    select id as repository_id, jsonb_array_elements_text(tracked_rows_added)::meta.row_id as row_id
    from repository;
