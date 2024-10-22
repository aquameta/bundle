------------------------------------------------------------------------------
-- DB / WORKING COPY
------------------------------------------------------------------------------

--
-- get_db_commit_rows()
--

create type row_exists as( row_id meta.row_id, exists boolean );
create or replace function _get_db_commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns setof row_exists as $$
declare
    rel record;
    stmts text[] := '{}';
    literals_stmt text;
    pk_comparison_stmt text;
begin
    if not delta._commit_exists( _commit_id ) then
        -- raise warning 'get_db_commit_rows(): Commit with id % does not exist.', _commit_id;
        return;
    end if;

/*
    WIP:

    -- is the supplied commit the head commit?  if so, use head_commit_row mat view instead of
    -- commit_rows() for much speed
    select repository_id from delta.commit where commit_id = _commit_id into _repository_id;
    if _commit_id = delta._head_commit_id(repository_id) then
        commit_rows_stmt := 'delta.get_head_commit_rows';
    else
        commit_rows_stmt := 'delta._get_commit_rows(_commit_id) row_id'
    end if;
*/

    -- for each relation in this commit
    for rel in
        select
            (row_id::meta.relation_id).name as relation_name,
            (row_id::meta.relation_id).schema_name as schema_name,
            (row_id).pk_column_names as pk_column_names
        from delta._get_commit_rows(_commit_id) row_id
        where row_id::meta.relation_id =
            case
                when _relation_id is null then row_id::meta.relation_id
                else _relation_id
            end
        group by row_id::meta.relation_id, (row_id).pk_column_names
    loop

        -- for this relation, select the commit_rows that are in this relation, and also in this
        -- repository, and inner join them with the relation's data, breaking it out into one row per
        -- field.

        -- TODO: check that each relation exists and still has the same primary key

        -- generate the pk comparisons line
        pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, rel.pk_column_names, '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');

        stmts := array_append(stmts, format('
            select row_id, x.%I is not null as exists
            from delta._get_commit_rows(%L, meta.relation_id(%L,%L)) row_id
                left join %I.%I x on
                    %s and
                    (row_id).schema_name = %L and
                    (row_id).relation_name = %L',
            rel.pk_column_names[1], -- 1 is ok here because we're just checking for exist w/ left join & pks cannot be null.  TODO: non-table_rel??
            _commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            pk_comparison_stmt,
            rel.schema_name,
            rel.relation_name
        )
    );
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    -- raise debug 'literals_stmt: %', literals_stmt;

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
    select * from delta._get_db_commit_rows(delta._head_commit_id(repository_id))
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
   a) start with the contents of rowset_row for this commit, then LEFT JOIN with
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
rowset_row_field, non-matching hashes will be fields changed.  When you OUTER
JOIN, it'll pick up new fields (from new columns presumably).
*/


create or replace function _get_db_commit_fields(commit_id uuid) returns setof delta.field_hash as $$
declare
    rel record;
    stmts text[] = '{}';
    literals_stmt text;
    pk_comparison_stmt text;
begin
    -- all relations in the head commit
    for rel in
        select distinct
            (row_id::meta.relation_id).name as relation_name,
            (row_id::meta.relation_id).schema_name as schema_name,
            (row_id).pk_column_names as pk_column_names
        from delta._get_commit_rows(commit_id) row_id
    loop
        -- TODO: check that each relation exists and has not been deleted.
        -- currently, when that happens, this function will fail.

        -- for each relation, select head commit rows in this relation and also
        -- in this repository, and inner join them with the relation's data,
        -- into one row per field

        -- FIXME: pk_column_names, pk_values
        pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, '{}'::text[], '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');
        stmts := array_append(stmts, format('
            select row_id, jsonb_each_text(to_jsonb(x)) as keyval
            from delta._get_db_commit_rows(%L, meta.relation_id(%L,%L)) row_id
                left join %I.%I x on
                    %s and
                    (row_id).schema_name = %L and
                    (row_id).relation_name = %L',
            commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            pk_comparison_stmt,
            rel.schema_name,
            rel.relation_name
        )
    );
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    if literals_stmt = '' then return; end if;

    -- wrap stmt to beautify columns
    literals_stmt := format('
        select
            meta.field_id((row_id).schema_name,(row_id).relation_name, (row_id).pk_column_names, (row_id).pk_values, (keyval).key),
            delta.hash((keyval).value)::text as value_hash
        from (%s) fields;',
        literals_stmt
    );

    -- raise notice 'literals_stmt: %', literals_stmt;

    return query execute literals_stmt;

end
$$ language plpgsql;


--
-- _get_db_head_commit_fields()
create or replace function _get_db_head_commit_fields(_repository_id uuid) returns setof delta.field_hash as $$
    select * from delta._get_db_commit_fields(delta._head_commit_id(_repository_id));
$$ language sql;

--
-- get_db_row_fields_obj()
--
-- returns a jsonb object whose keys are column names and values are live db values

create or replace function _get_db_row_fields_obj(_row_id meta.row_id) returns jsonb as $$
declare
    stmt text;
    obj jsonb;
begin
    stmt := format('select to_json(xx) from %I.%I xx where %s',
        _row_id.schema_name,
        _row_id.relation_name,
        meta._pk_stmt(_row_id, '%1$I = %2$L')
    );

    execute stmt into obj;
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
        _row_id.schema_name,
        _row_id.relation_name,
        meta._pk_stmt(_row_id, '%1$I = %2$L')
    );
    execute stmt into obj;
    -- raise notice 'get_db_row_field_hashes_obj: %', obj;

    -- hash values into hashed_obj, for return
    for key, value in select * from jsonb_each_text(obj) loop
        hashed_obj := hashed_obj || jsonb_build_object(key, delta.hash(value));
    end loop;

    return hashed_obj;
end;
$$ language plpgsql;





/*
big diff queries:

select *
from get_db_commit_fields(head_commit_id('io.aquadelta.test')) dbcf
full outer join commit_fields(head_commit_id('io.aquadelta.test')) cf on dbcf.field_id = cf.field_id
where
    dbcf.value_hash != cf.value_hash or
    dbcf.field_id is null
    or cf.field_id is null;



select * from _get_db_commit_rows(head_commit_id('io.aquadelta.test')) dbcr
full outer join _get_commit_rows(head_commit_id('io.aquadelta.test')) cr on dbcr.row_id = cr.row_id
where
    dbcr.row_id is null
    or cr.row_id is null
    or dbcr.exists = false;
*/
