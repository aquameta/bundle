------------------------------------------------------------------------------
-- STAGE / DB COMPARISON / WORKING COPY FUNCTIONS
--
-- This file consolidates:
--   1. DB State Functions - Read current database state and compare to commits
--   2. Stage Operations - Manipulate the staging area
--   3. Stage-Dependent Comparisons - Compare staged changes to database/commit state
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- PART 1: DB STATE FUNCTIONS
-- Functions that read current database state and compare to commit snapshots
------------------------------------------------------------------------------


--
-- get_db_commit_rows()
--
-- NOTE: row_exists type is defined in types.sql

create or replace function _get_db_commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns setof row_exists as $$
declare
    rel record;
    stmts text[] := '{}';
    literals_stmt text;
    pk_comparison_stmt text;
begin
    if not bundle._commit_exists( _commit_id ) then
        -- raise warning 'get_db_commit_rows(): Commit with id % does not exist.', _commit_id;
        return;
    end if;

/*
    WIP:

    -- is the supplied commit the head commit?  if so, use head_commit_row mat view instead of
    -- commit_rows() for much speed
    select repository_id from bundle.commit where commit_id = _commit_id into _repository_id;
    if _commit_id = bundle._head_commit_id(repository_id) then
        commit_rows_stmt := 'bundle.get_head_commit_rows';
    else
        commit_rows_stmt := 'bundle._get_commit_rows(_commit_id) row_id'
    end if;
*/

    -- for each relation in this commit
    for rel in
        select
            row_id->>'relation_name' as relation_name,
            row_id->>'schema_name' as schema_name,
            row_id->'pk_column_names' as pk_column_names_jsonb
        from bundle._get_commit_rows(_commit_id) row_id
        where meta.row_id_to_relation_id(row_id) =
            case
                when _relation_id is null then meta.row_id_to_relation_id(row_id)
                else _relation_id
            end
        group by row_id->>'relation_name', row_id->>'schema_name', row_id->'pk_column_names'
    loop
        -- Convert JSONB array to PostgreSQL text array
        declare
            pk_column_names text[];
        begin
            select array_agg(value::text) from jsonb_array_elements_text(rel.pk_column_names_jsonb) into pk_column_names;

        -- raise notice '#### _db_commit_rows rel: %', rel;

        -- for this relation, select the commit_rows that are in this relation, and also in this
        -- repository, and inner join them with the relation's data, breaking it out into one row per
        -- field.

        -- TODO: check that each relation exists and still has the same primary key

        -- generate the pk comparisons line
        -- FIXME: fails on composite keys because row('a','b','c') != '(a,b,c)':
        -- 'ERROR:  input of anonymous composite types is not implemented' (bug in pg)
        pk_comparison_stmt := meta._pk_stmt(pk_column_names, pk_column_names, 'x.%1$I::text = (row_id)->''pk_values''->>(%3$s-1)');
        -- WAS: pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, rel.pk_column_names, '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');


        stmts := array_append(stmts, format('
            select row_id, x.%I is not null as exists
            from bundle._get_commit_rows(%L, meta.make_relation_id(%L,%L)) row_id
                left join %I.%I x on
                    %s and
                    (row_id)->>''schema_name'' = %L and
                    (row_id)->>''relation_name'' = %L',
            pk_column_names[1], -- 1 is ok here because we're just checking for exist w/ left join & pks cannot be null.  TODO: non-table_rel??
            _commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            pk_comparison_stmt,
            rel.schema_name,
            rel.relation_name
        ));
        end;
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    -- raise notice 'literals_stmt: %', literals_stmt;

    if literals_stmt != '' then
        return query execute literals_stmt;
    else
        return;
    end if;
end;
$$ language plpgsql;


--
-- get_db_head_commit_rows()
--

create or replace function _get_db_head_commit_rows( repository_id uuid ) returns setof row_exists as $$
    select * from bundle._get_db_commit_rows(bundle._head_commit_id(repository_id))
$$ language sql;


--
-- get_db_commit_fields()
--

/*
Returns a field_hash for live database values for a given commit.  It returns
*all* columns present, without regard to what columns or fields are actually
being tracked in the database.  Think `select * from my.table`.  This means:

- when a field is changed since the last commit, the change will be reflected here
- when a column is added since the provided commit, it will be present in this list
- when a column is deleted since the provided commit, it will be absent from this list

Steps:

1) make a list of the relations of all rows in the supplied commit

2) for each relation "x":
   a) start with the contents of get_commit_rows(), then LEFT JOIN with
      the relation, on

      rowset_row.row_id.pk_value IS NOT DISTINCT FROM x.$pk_column_name

      (NOT DISTINCT because null != null, and that's a match in this situation)

   b) call jsonb_each_text(to_json(x)) which makes a row for each field
   c) construct the field's field_id, and sha256 the field's value

3) UNION all these field_id + hashes from all these relations together and
   return a big list of field_hash records, (meta.field_id, value_hash)

It returns the value hash of all fields on any row in the supplied commit, with
its value hash.  Typically, this would be called with the repo's head commit
(repository.head_commit_id), though it can be used to diff against previous
commits as well.

It is useful for generating a repository's row list with change info, as well
as the stage.  When you INNER JOIN this function's results against
get_commit_fields(), non-matching hashes will be fields changed.  When you OUTER
JOIN, it'll pick up new fields (from new columns presumably).
*/


create or replace function _get_db_commit_fields(commit_id uuid) returns setof bundle.field_hash as $$
declare
    rel record;
    stmts text[] = '{}';
    literals_stmt text;
    pk_comparison_stmt text;
begin
    -- all relations in the head commit
    for rel in
        select distinct
            (meta.row_id_to_relation_id(row_id))->>'name' as relation_name,
            (meta.row_id_to_relation_id(row_id))->>'schema_name' as schema_name,
            row_id->'pk_column_names' as pk_column_names
        from bundle._get_commit_rows(commit_id) row_id
    loop
        -- for each relation, select head commit rows in this relation and also
        -- in this repository, and inner join them with the relation's data,
        -- into one row per field

        -- TODO: check that each relation exists and has not been deleted.
        -- currently, when that happens, this function will fail.

        -- Convert JSONB array to PostgreSQL text array
        declare
            pk_column_names text[];
        begin
            select array_agg(value::text) from jsonb_array_elements_text(rel.pk_column_names) into pk_column_names;

        pk_comparison_stmt := meta._pk_stmt(pk_column_names, '{}'::text[], 'x.%1$I::text = (row_id)->''pk_values''->>(%3$s-1)');
        -- WAS: pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, '{}'::text[], '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');

        stmts := array_append(stmts, format('
            select row_id, jsonb_each_text(bundle.row_to_jsonb_hash_obj(x)) as keyval
            from bundle._get_db_commit_rows(%L, meta.make_relation_id(%L,%L)) row_id
                left join %I.%I x on
                    %s and
                    (row_id)->>''schema_name'' = %L and
                    (row_id)->>''relation_name'' = %L',
            commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            pk_comparison_stmt,
            rel.schema_name,
            rel.relation_name
        ));
        end;
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    if literals_stmt = '' then return; end if;

    -- wrap stmt to beautify columns
    literals_stmt := format('
        select
            meta.make_field_id(row_id, (keyval).key),
            -- TODO bundle.hash((keyval).value)::text as value_hash
            ((keyval).value)::text as value_hash
        from (%s) fields;',
        literals_stmt
    );

    -- raise notice 'literals_stmt: %', literals_stmt;

    return query execute literals_stmt;

end
$$ language plpgsql;


--
-- _get_db_head_commit_fields()
create or replace function _get_db_head_commit_fields(_repository_id uuid) returns setof bundle.field_hash as $$
    select * from bundle._get_db_commit_fields(bundle._head_commit_id(_repository_id));
$$ language sql;



/*
--
-- get_db_row_fields_obj()
--
-- returns a jsonb object whose keys are column names and values are live db values.
-- one-row at a time.  called from commit().  slow and crappy, shouldn't be used

create or replace function _get_db_row_fields_obj(_row_id meta.row_id) returns jsonb as $$
declare
    stmt text;
    obj jsonb;
begin
    stmt := format('select * from %I.%I xx where %s',
        _row_id->>'schema_name',
        _row_id->>'relation_name',
        -- BAD!  This slows things down like 10x:
        -- meta._pk_stmt(_row_id, '%1$I::text = %2$L')
        meta._pk_stmt(_row_id, '%1$I = %2$L')

    );

    obj := bundle.query_to_jsonb_text(stmt);
    return obj;
end;
$$ language plpgsql;



--
-- get_db_row_field_hashes_obj()
--
-- returns a jsonb object whose keys are column names and values are live db value hashes
-- TODO: can this be done inline so values aren't stored in memory in temp obj?

create or replace function _get_db_row_field_hashes_obj(_row_id meta.row_id) returns jsonb as $$
declare
    stmt text;
    obj jsonb;
    hashed_obj jsonb := '{}';
    key text;
    value text;
begin
    -- build key: value temp obj
    stmt := format('select to_json(xx) from %I.%I xx where %s',
        _row_id->>'schema_name',
        _row_id->>'relation_name',
        meta._pk_stmt(_row_id, '%1$I = %2$L')
    );
    execute stmt into obj;
    -- raise notice 'get_db_row_field_hashes_obj: %', obj;

    -- hash values into hashed_obj, for return
    for key, value in select * from jsonb_each_text(obj) loop
        -- hashed_obj := hashed_obj || jsonb_build_object(key, TODO bundle.hash(value));
        hashed_obj := hashed_obj || jsonb_build_object(key, value::text);
    end loop;

    return hashed_obj;
end;
$$ language plpgsql;
*/

--
-- tracked
--

create or replace function _get_db_tracked_rows_added( _repository_id uuid )
returns table(row_id meta.row_id, row_exists boolean) as $$
    select
        elem::meta.row_id as row_id,
        meta.row_exists(elem::meta.row_id) as row_exists
    from bundle.repository r,
         lateral jsonb_array_elements(r.tracked_rows_added) elem
    where r.id = _repository_id;
$$ language sql;

create or replace function get_db_tracked_rows_added( repository_name text )
returns table(row_id meta.row_id, row_exists boolean) as $$
    select * from bundle._get_db_tracked_rows_added(
        bundle.repository_id(repository_name)
    );
$$ language sql;


--
-- stage
--

create or replace function _get_db_stage_rows_added( _repository_id uuid )
returns table(row_id meta.row_id, row_exists boolean) as $$
    select
        elem::meta.row_id as row_id,
        meta.row_exists(elem::meta.row_id) as row_exists
    from bundle.repository r,
         lateral jsonb_array_elements(r.stage_rows_to_add) elem
    where r.id = _repository_id;
$$ language sql;

/*

failure:

create or replace function _get_db_rowset_fields_obj(rowset jsonb) returns jsonb as $$
declare
    relations meta.relation_id[];
    rel_id meta.relation_id;
    col_id meta.column_id;

    col_stmt text;
    col_stmts text[];
    stmt text;
    stmts text[] = '{}';

    results jsonb;
begin
    raise notice 'rowset: %', rowset;
    -- relations in the rowset
    foreach rel_id in array bundle._get_rowset_relations(rowset) loop

        -- builds a key/val to pass to jsonb_build_object
        -- e.g.
        -- 'id', bundle.hash(r.id::text),               -- "id": '\x123123123'
        -- 'schema_id', bundle.hash(r.schema_id::text)

        col_stmts := '{}';
        foreach col_id in array meta.get_columns(rel_id) loop
            col_stmts := array_append(col_stmts, format('%L, bundle.hash(r.%I::text)',
                col_id->>'name',
                col_id->>'name',
                col_id->>'name')
            );
        end loop;

        col_stmt := array_to_string(col_stmts, E',\n');
        raise notice 'col_stmt: %', col_stmt;

        stmt := format('select meta.make_row_id(%L,%L,%L,%L) row_id, jsonb_build_object(%s) obj
                from %I.%I r
                join jsonb_array_elements_text(%s::jsonb) rs on %s',

            -- row_id
            rel_id->>'schema_name',
            rel_id->>'name',
            'x',
            'x',

            -- col stmts
            col_stmt,

            -- from relation
            rel_id->>'schema_name',
            rel_id->>'name',

            -- rowset???
            quote_literal(rowset::text), -- inefficient as heck but thought you could use USING.  can't.

            '1=1' -- meta._pk_stmt(..)
        );

        stmts := array_append(stmts, stmt);
    end loop;

    stmt := array_to_string(stmts,E'\nunion\n');

    raise notice '_get_db_rowset_fields_obj stmt: %', stmt;

    -- wrap the big union stmt with an object_agg to pull it all together
    stmt := format('select jsonb_object_agg(row_id, obj) from (%s) s(row_id, obj)',
        stmt
    );

    execute stmt into results using rowset;
    raise notice 'RESULTS: %', results;
    return results;
end;
$$ language plpgsql;
*/




/*
big diff queries:

select *
from get_db_commit_fields(head_commit_id('io.bundle.test')) dbcf
full outer join commit_fields(head_commit_id('io.bundle.test')) cf on dbcf.field_id = cf.field_id
where
    dbcf.value_hash != cf.value_hash or
    dbcf.field_id is null
    or cf.field_id is null;



select * from _get_db_commit_rows(head_commit_id('io.bundle.test')) dbcr
full outer join _get_commit_rows(head_commit_id('io.bundle.test')) cr on dbcr.row_id = cr.row_id
where
    dbcr.row_id is null
    or cr.row_id is null
    or dbcr.exists = false;
*/


------------------------------------------------------------------------------
-- PART 2: STAGE OPERATIONS
-- Functions that manipulate the staging area
------------------------------------------------------------------------------



-------------------------------------------------
-- Staging / Unstaging Action Functions
-------------------------------------------------

--
-- stage_tracked_row()
--

create or replace function _stage_tracked_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    begin
        -- assert repository exists
        if not bundle._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- check that it's not already staged
        if meta.row_exists(meta.make_row_id('bundle','stage_row_to_add', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;

        if exists (
            select 1 from bundle._get_head_commit_rows(_repository_id)
            where row_id = _row_id
        ) then
            raise exception 'Row with row_id % is already in the repository.', _row_id;
        end if;

        -- untrack
        perform bundle._untrack_tracked_row(_repository_id, _row_id);

        -- stage
        update bundle.repository
        set stage_rows_to_add = stage_rows_to_add || _row_id
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_tracked_row( repository_name text, row_id meta.row_id )
returns void as $$
    begin
        -- assert repository exists
        if not bundle.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform bundle._stage_tracked_row(
            bundle.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- unstage_tracked_row()
--

create or replace function _unstage_tracked_row(_repository_id uuid, _row_id meta.row_id)
returns void language plpgsql as $$
begin
    -- assert repository exists
    if not bundle._repository_exists(_repository_id) then
        raise exception 'Repository with id % does not exist.', _repository_id;
    end if;

    -- remove from stage_rows_to_add jsonb array
    update bundle.repository
    set stage_rows_to_add = (
        select coalesce(jsonb_agg(elem.value), '[]'::jsonb)
        from jsonb_array_elements(stage_rows_to_add) elem(value)
        where elem.value != to_jsonb(_row_id)
    )
    where id = _repository_id;

    -- re-track the row (correct column: tracked_rows_added)
    update bundle.repository
    set tracked_rows_added = coalesce(tracked_rows_added, '[]'::jsonb) || to_jsonb(_row_id)
    where id = _repository_id
    and not (coalesce(tracked_rows_added, '[]'::jsonb) @> jsonb_build_array(to_jsonb(_row_id)));
end;
$$;




--
-- stage_row_to_remove()
--

create or replace function _stage_row_to_remove( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not bundle._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        if not exists (
            select 1 from bundle._get_head_commit_rows(_repository_id)
            where row_id = _row_id
        ) then
            raise exception 'Row with row_id % is not in the head commit.', _row_id;
        end if;

        -- stage
        update bundle.repository
        set stage_rows_to_remove = stage_rows_to_remove || _row_id
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_to_remove( repository_name text, row_id meta.row_id )
returns void as $$
    begin

        -- assert repository exists
        if not bundle.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform bundle._stage_row_to_remove(
            bundle.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- unstage_row_to_remove()
--
-- Removes a staged row (add or delete) from the stage.  Split these up?

create or replace function _unstage_row_to_remove( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from bundle.stage_row_to_add sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        update bundle.repository
        set stage_rows_to_remove = (
            select coalesce(jsonb_agg(elem.value), '[]'::jsonb)
            from jsonb_array_elements(stage_rows_to_remove) elem(value)
            where elem.value != _row_id::jsonb
        )
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function unstage_row_to_remove( _repository_id uuid, row_id meta.row_id )
returns void as $$
    select bundle._unstage_row_to_remove(_repository_id, row_id);
$$ language sql;


--
-- stage a field change
--

create or replace function _stage_field_to_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
    begin
        -- TODO: assert field is changed and part of repo
        update bundle.repository
        -- obj approach: set stage_fields_to_change = stage_fields_to_change || jsonb_build_object(_field_id::text, meta.field_id_literal_value(_field_id))
        set stage_fields_to_change = stage_fields_to_change || _field_id
        where id = _repository_id;
        return true;
    end;
$$ language plpgsql;

--
-- unstage a field change
--

create or replace function _unstage_field_to_change(_repository_id uuid, _field_id meta.field_id)
returns boolean
language plpgsql as $$
begin
    update bundle.repository
    set stage_fields_to_change = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(stage_fields_to_change) as elem
        where elem != _field_id::jsonb
    )
    where id = _repository_id;
    return true;
end;
$$;

create or replace function unstage_field_to_change( repository_name text, _field_id meta.field_id ) returns void as $$
    select bundle._unstage_field_to_change(bundle.repository_id(repository_name), _field_id);
$$ language sql;


--
-- empty_stage()
--

create or replace function _empty_stage( _repository_id uuid ) returns void as $$
    begin
        update bundle.repository set stage_rows_to_add = '[]' where id = _repository_id;
        update bundle.repository set stage_rows_to_remove = '[]' where id = _repository_id;
        update bundle.repository set stage_fields_to_change = '[]' where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function empty_stage( repository_name text ) returns void as $$
    select bundle._empty_stage(bundle.repository_id(repository_name));
$$ language sql;



-------------------------------------------------
-- Set Views / Functions
-- Convention: _get_*()
-------------------------------------------------

--
-- get_stage_rows_to_add()
--

create or replace function _get_stage_rows_to_add( _repository_id uuid ) returns table (repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements(stage_rows_to_add)
    from bundle.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_add as
select id as repository_id, jsonb_array_elements(stage_rows_to_add) as row_id
from bundle.repository;


--
-- get_stage_rows_to_remove()
--

create or replace function _get_stage_rows_to_remove( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements(stage_rows_to_remove)
    from bundle.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_remove as
select id as repository_id, jsonb_array_elements(stage_rows_to_remove) as row_id
from bundle.repository;


--
-- get_stage_fields_to_change()
--

create or replace function _get_stage_fields_to_change( _repository_id uuid ) returns setof meta.field_id as $$
    select jsonb_array_elements(stage_fields_to_change)
    from bundle.repository
    where id = _repository_id;
$$ language sql;

create view stage_field_to_change as
    -- select id, jsonb_array_elements(stage_fields_to_change)
select id as repository_id, jsonb_array_elements(stage_fields_to_change) as field_id
from bundle.repository;


--
-- _is_staged()
--

create or replace function _is_staged( repository_id uuid, row_id meta.row_id ) returns boolean as $$
begin
    return (
        select stage_rows_to_add @> jsonb_build_array(row_id)
        from bundle.repository
        where id = repository_id
    );
end;
$$ language plpgsql;



--
-- get_tracked_rows()
-- Returns *all* tracked rows: Newly tracked, staged and head_commit rows

create or replace function _get_tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from bundle._get_head_commit_rows(_repository_id)

    -- ...plus newly tracked rows
    union

    select jsonb_array_elements(r.tracked_rows_added)::meta.row_id
    from bundle.repository r
    where r.id = _repository_id

    -- plus staged rows
    union

    select jsonb_array_elements(r.stage_rows_to_add)::meta.row_id
    from bundle.repository r
    where r.id = _repository_id
$$ language sql;

create or replace function get_tracked_rows( repository_name text ) returns setof meta.row_id as $$
    select bundle._get_tracked_rows(
        bundle.repository_id(repository_name)
    );
$$ language sql;



create or replace function _get_offstage_deleted_rows(
    _repository_id uuid,
    relation_id_filter meta.relation_id default null
) returns setof meta.row_id as $$
    -- rows deleted from head commit
    select row_id
    from bundle._get_db_head_commit_rows(_repository_id)
    where exists = false
    and (relation_id_filter is null or meta.row_id_to_relation_id(row_id) = relation_id_filter)

    except

    -- minus those that have been staged for deletion
    select jsonb_array_elements(r.stage_rows_to_remove)::meta.row_id
    from bundle.repository r where r.id = _repository_id;
$$ language sql;


--
-- get_stage_updated_fields() TODO
--

--
-- get_offstage_updated_fields()
--
-- NOTE: field_hash_diff type is defined in types.sql

create or replace function _get_offstage_updated_fields(
    _repository_id uuid,
    relation_id_filter meta.relation_id default null
) returns setof bundle.field_hash_diff as $$
    -- fields whos commit hash is different from db hash
    select
        hcf.field_id as field_id,
        dbf.value_hash as db_value_hash,
        hcf.value_hash as commit_value_hash
    -- fields from head commit
    from bundle._get_head_commit_fields(_repository_id) hcf
        -- join with existing rows to exclude deleted rows from field change detection
        join bundle._get_db_head_commit_rows(_repository_id) existing_rows
            on meta.field_id_to_row_id(hcf.field_id) = existing_rows.row_id
        -- left joined because db_fields() excludes dropped columns and columns may have been dropped
        left join bundle._get_db_head_commit_fields(_repository_id) dbf on dbf.field_id = hcf.field_id
        -- exclude staged fields
        left join bundle._get_db_stage_fields_to_change(_repository_id, relation_id_filter) sfc on sfc.field_id = hcf.field_id
    -- where value is different
    where existing_rows.exists = true
    and hcf.value_hash != dbf.value_hash -- hash should never be NULL so we can use != here
    -- and it's not on the stage
    and sfc.field_id is null
    -- relation filter
    and (relation_id_filter is null or meta.field_id_to_relation_id(hcf.field_id) = relation_id_filter)

/*
    except

    select field_id, value_hash from bundle._get_db_stage_fields_to_change(_repository_id, relation_id_filter);
*/
$$ language sql;


--
-- _get_stage_rows()
--
-- NOTE: stage_row type is defined in types.sql

create or replace function _get_stage_rows( _repository_id uuid ) returns setof stage_row as $$
    select row_id, false as new_row from (
        -- head_commit_row
        select hcr.row_id as row_id
        from bundle._get_head_commit_rows(_repository_id) hcr

        except

        -- ...minus deleted rows
        select jsonb_array_elements(stage_rows_to_remove)::meta.row_id as row_id
        from bundle.repository r
        where r.id = _repository_id

    ) remaining_rows

    union

    -- ...plus staged rows
    select jsonb_array_elements(r.stage_rows_to_add)::meta.row_id, true as new_row
    from bundle.repository r
    where r.id = _repository_id

$$ language sql;


-------------------------------------------------
-- Macro-ops
-------------------------------------------------

--


--
-- stage_tracked_rows()
--

create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
declare
    _tracked_rows_obj jsonb;
begin
    -- append tracked_rows_added to stage_rows_to_add
    update bundle.repository
    set stage_rows_to_add = stage_rows_to_add || tracked_rows_added
    where id = _repository_id;

    -- clear repository.tracked_rows_added
    update bundle.repository set tracked_rows_added = '[]'::jsonb
    where id = _repository_id;

end;
$$ language plpgsql;

create or replace function stage_tracked_rows( repository_name text ) returns void as $$
    select bundle._stage_tracked_rows(bundle.repository_id(repository_name))
$$ language sql;


--
-- stage_updated_fields()
-- stages all changed unstaged field changes on a repository

create or replace function _stage_updated_fields( _repository_id uuid, relation_id_filter meta.relation_id default null ) returns void as $$
    declare
        updated_fields jsonb;
        start_time timestamp := clock_timestamp();
    begin
        -- assert repository exists
        if not bundle._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        with updated_fields as (
            select jsonb_agg(f.field_id) field
            from bundle._get_offstage_updated_fields(_repository_id) f
            where (relation_id_filter is null or meta.field_id_to_relation_id(f.field_id) = relation_id_filter)
        )
        update bundle.repository
        set stage_fields_to_change = stage_fields_to_change || coalesce(updated_fields.field, '[]'::jsonb)
        from updated_fields
        where id = _repository_id;

        raise notice '_stage_updated_fields() ... %s', bundle.clock_diff(start_time);
    end;
$$ language plpgsql;

create or replace function stage_updated_fields( repository_name text, relation_id_filter meta.relation_id default null ) returns void as $$
    select bundle._stage_updated_fields(bundle.repository_id(repository_name), relation_id_filter);
$$ language sql;


--
-- stage_deleted_rows()
-- stage all off-stage deleted rows for removal
--

create or replace function _stage_deleted_rows( _repository_id uuid, relation_id_filter meta.relation_id default null ) returns void as $$
    declare
        start_time timestamp := clock_timestamp();
    begin
        -- assert repository exists
        if not bundle._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        update bundle.repository
        set stage_rows_to_remove = stage_rows_to_remove || coalesce(
            (select to_jsonb(array_agg(r)) lateral from bundle._get_offstage_deleted_rows (_repository_id, relation_id_filter) r),
            '[]'::jsonb
        )
        where id = _repository_id;
        raise notice '_stage_deleted_rows() ... %s', bundle.clock_diff(start_time);
    end;
$$ language plpgsql;

create or replace function stage_deleted_rows( repository_name text, relation_id_filter meta.relation_id default null ) returns void as $$
    select bundle._stage_deleted_rows(bundle.repository_id(repository_name), relation_id_filter);
$$ language sql;


--
-- unstage_tracked_row()
-- remove a row from stage_rows_to_add (move back to tracked_rows_added)
--

create or replace function _unstage_tracked_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
declare
    row_id_json jsonb := to_jsonb(_row_id);
begin
    -- remove from stage_rows_to_add
    update bundle.repository
    set stage_rows_to_add = (
        select coalesce(jsonb_agg(elem), '[]'::jsonb)
        from jsonb_array_elements(stage_rows_to_add) elem
        where elem != row_id_json
    )
    where id = _repository_id;

    -- add back to tracked_rows_added
    update bundle.repository
    set tracked_rows_added = tracked_rows_added || jsonb_build_array(row_id_json)
    where id = _repository_id;
end;
$$ language plpgsql;

create or replace function unstage_tracked_row( repository_name text, _row_id meta.row_id ) returns void as $$
    select bundle._unstage_tracked_row(bundle.repository_id(repository_name), _row_id);
$$ language sql;


--
-- unstage_all()
-- clear all staged items, moving rows back to tracked_rows_added
--

create or replace function unstage_all( repository_name text ) returns void as $$
declare
    repo bundle.repository;
begin
    select * into repo from bundle.repository r where r.name = repository_name;
    if not found then
        raise exception 'Repository not found: %', repository_name;
    end if;

    -- move staged rows to add back to tracked_rows_added, clear all staging arrays
    update bundle.repository
    set tracked_rows_added = tracked_rows_added || coalesce(stage_rows_to_add, '[]'::jsonb),
        stage_rows_to_add = '[]'::jsonb,
        stage_rows_to_remove = '[]'::jsonb,
        stage_fields_to_change = '[]'::jsonb
    where id = repo.id;
end;
$$ language plpgsql;




------------------------------------------------------------------------------
-- PART 3: STAGE-DEPENDENT DB COMPARISONS
-- Functions that depend on stage operations and compare staged state
------------------------------------------------------------------------------


create or replace function _get_db_stage_rows_added( _repository_id uuid )
returns table(row_id meta.row_id, row_exists boolean) as $$
    select
        elem::meta.row_id as row_id,
        meta.row_exists(elem::meta.row_id) as row_exists
    from bundle.repository r,
         lateral jsonb_array_elements(r.stage_rows_to_add) elem
    where r.id = _repository_id;
$$ language sql;

create or replace function _get_db_stage_fields_to_change(
    _repository_id uuid,
    relation_id_filter meta.relation_id default null
)
returns table (
    field_id meta.field_id,
    row_exists boolean,
    column_exists boolean,
    field_is_changed boolean,
    db_value_hash text
) as $$
    select
        staged.field_id,
        coalesce(db_rows.exists, false) as row_exists,
        db_fields.field_id is not null as column_exists,
        coalesce(commit_fields.value_hash != db_fields.value_hash, false) as field_is_changed,
        db_fields.value_hash as db_value_hash
    from (
        select jsonb_array_elements(stage_fields_to_change)::meta.field_id as field_id
        from bundle.repository
        where id = _repository_id
    ) staged
    -- check if row exists
    left join bundle._get_db_head_commit_rows(_repository_id) db_rows
        on meta.field_id_to_row_id(staged.field_id) = db_rows.row_id
    -- get current db value (tells us if column exists)
    left join bundle._get_db_head_commit_fields(_repository_id) db_fields
        on staged.field_id = db_fields.field_id
    -- get committed value to compare
    left join bundle._get_head_commit_fields(_repository_id) commit_fields
        on staged.field_id = commit_fields.field_id
    where relation_id_filter is null
       or meta.field_id_to_relation_id(staged.field_id) = relation_id_filter;
$$ language sql;


create or replace function _get_db_offstage_updated_fields(
    _repository_id uuid,
    relation_id_filter meta.relation_id default null
)
returns table(field_id meta.field_id, db_value_hash text, commit_value_hash text, row_exists boolean)
as $$
    select
        f.field_id,
        f.db_value_hash,
        f.commit_value_hash,
        meta.row_exists(meta.field_id_to_row_id(f.field_id)) as row_exists
    from bundle._get_offstage_updated_fields(_repository_id, relation_id_filter) f;
$$ language sql;


create or replace function _get_db_stage_rows_to_remove(_repository_id uuid)
returns table(repository_id uuid, row_id meta.row_id, row_exists boolean)
as $$
    select
        s.repository_id,
        s.row_id,
        meta.row_exists(s.row_id) as row_exists
    from bundle._get_stage_rows_to_remove(_repository_id) s;
$$ language sql;


/*

failure:

create or replace function _get_db_rowset_fields_obj(rowset jsonb) returns jsonb as $$
declare
    relations meta.relation_id[];
    rel_id meta.relation_id;
    col_id meta.column_id;

    col_stmt text;
    col_stmts text[];
    stmt text;
    stmts text[] = '{}';

    results jsonb;
begin
    raise notice 'rowset: %', rowset;
    -- relations in the rowset
    foreach rel_id in array bundle._get_rowset_relations(rowset) loop

        -- builds a key/val to pass to jsonb_build_object
        -- e.g.
        -- 'id', bundle.hash(r.id::text),               -- "id": '\x123123123'
        -- 'schema_id', bundle.hash(r.schema_id::text)

        col_stmts := '{}';
        foreach col_id in array meta.get_columns(rel_id) loop
            col_stmts := array_append(col_stmts, format('%L, bundle.hash(r.%I::text)',
                col_id->>'name',
                col_id->>'name',
                col_id->>'name')
            );
        end loop;

        col_stmt := array_to_string(col_stmts, E',\n');
        raise notice 'col_stmt: %', col_stmt;

        stmt := format('select meta.make_row_id(%L,%L,%L,%L) row_id, jsonb_build_object(%s) obj
                from %I.%I r
                join jsonb_array_elements_text(%s::jsonb) rs on %s',

            -- row_id
            rel_id->>'schema_name',
            rel_id->>'name',
            'x',
            'x',

            -- col stmts
            col_stmt,

            -- from relation
            rel_id->>'schema_name',
            rel_id->>'name',

            -- rowset???
            quote_literal(rowset::text), -- inefficient as heck but thought you could use USING.  can't.

            '1=1' -- meta._pk_stmt(..)
        );

        stmts := array_append(stmts, stmt);
    end loop;

    stmt := array_to_string(stmts,E'\nunion\n');

    raise notice '_get_db_rowset_fields_obj stmt: %', stmt;

    -- wrap the big union stmt with an object_agg to pull it all together
    stmt := format('select jsonb_object_agg(row_id, obj) from (%s) s(row_id, obj)',
        stmt
    );

    execute stmt into results using rowset;
    raise notice 'RESULTS: %', results;
    return results;
end;
$$ language plpgsql;
*/




/*
big diff queries:

select *
from get_db_commit_fields(head_commit_id('io.bundle.test')) dbcf
full outer join commit_fields(head_commit_id('io.bundle.test')) cf on dbcf.field_id = cf.field_id
where
    dbcf.value_hash != cf.value_hash or
    dbcf.field_id is null
    or cf.field_id is null;



select * from _get_db_commit_rows(head_commit_id('io.bundle.test')) dbcr
full outer join _get_commit_rows(head_commit_id('io.bundle.test')) cr on dbcr.row_id = cr.row_id
where
    dbcr.row_id is null
    or cr.row_id is null
    or dbcr.exists = false;
*/
