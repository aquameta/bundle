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
            (row_id::meta.relation_id).name as relation_name,
            (row_id::meta.relation_id).schema_name as schema_name,
            (row_id).pk_column_names as pk_column_names
        from bundle._get_commit_rows(_commit_id) row_id
        where row_id::meta.relation_id =
            case
                when _relation_id is null then row_id::meta.relation_id
                else _relation_id
            end
        group by row_id::meta.relation_id, (row_id).pk_column_names
    loop
        -- raise notice '#### _db_commit_rows rel: %', rel;

        -- for this relation, select the commit_rows that are in this relation, and also in this
        -- repository, and inner join them with the relation's data, breaking it out into one row per
        -- field.

        -- TODO: check that each relation exists and still has the same primary key

        -- generate the pk comparisons line
        -- FIXME: fails on composite keys because row('a','b','c') != '(a,b,c)':
        -- 'ERROR:  input of anonymous composite types is not implemented' (bug in pg)
        pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, rel.pk_column_names, 'x.%1$I::text = (row_id).pk_values[%3$s]');
        -- WAS: pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, rel.pk_column_names, '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');


        stmts := array_append(stmts, format('
            select row_id, x.%I is not null as exists
            from bundle._get_commit_rows(%L, meta.make_relation_id(%L,%L)) row_id
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
rowset_row_field, non-matching hashes will be fields changed.  When you OUTER
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
            (row_id::meta.relation_id).name as relation_name,
            (row_id::meta.relation_id).schema_name as schema_name,
            (row_id).pk_column_names as pk_column_names
        from bundle._get_commit_rows(commit_id) row_id
    loop
        -- for each relation, select head commit rows in this relation and also
        -- in this repository, and inner join them with the relation's data,
        -- into one row per field

        -- TODO: check that each relation exists and has not been deleted.
        -- currently, when that happens, this function will fail.

        pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, '{}'::text[], 'x.%1$I::text = (row_id).pk_values[%3$s]');
        -- WAS: pk_comparison_stmt := meta._pk_stmt(rel.pk_column_names, '{}'::text[], '(row_id).pk_values[%3$s] = x.%1$I::text', ' and ');

        stmts := array_append(stmts, format('
            select row_id, jsonb_each_text(bundle.row_to_jsonb_hash_obj(x)) as keyval
            from bundle._get_db_commit_rows(%L, meta.make_relation_id(%L,%L)) row_id
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
            meta.make_field_id((row_id).schema_name,(row_id).relation_name, (row_id).pk_column_names, (row_id).pk_values, (keyval).key),
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
        _row_id.schema_name,
        _row_id.relation_name,
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
        _row_id.schema_name,
        _row_id.relation_name,
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


/*
create or replace function _get_db_stage_fields_to_change( _repository_id uuid ) returns setof field_hash as $$
    with fields as
        select jsonb_array_elements_text(stage_fields_to_change)::meta.field_id as field_id
        from bundle.repository where id = _repository_id
    select
        field_id, bundle.hash(meta.field_id_literal_value(field_id))
    from field;
end;
$$ language sql;
*/


create or replace function _get_db_stage_fields_to_change(_repository_id uuid, relation_id_filter meta.relation_id default null)
returns setof field_hash as $$
    select
        field_id::meta.field_id,
        bundle.hash(meta.field_id_literal_value(field_id::meta.field_id)) as field_hash
    from (
        select jsonb_array_elements_text(stage_fields_to_change) as field_id
        from bundle.repository
        where id = _repository_id
    ) as fields
    where (relation_id_filter is null or fields.field_id::meta.field_id::meta.relation_id = relation_id_filter)
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
                col_id.name,
                col_id.name,
                col_id.name)
            );
        end loop;

        col_stmt := array_to_string(col_stmts, E',\n');
        raise notice 'col_stmt: %', col_stmt;

        stmt := format('select meta.make_row_id(%L,%L,%L,%L) row_id, jsonb_build_object(%s) obj
                from %I.%I r
                join jsonb_array_elements_text(%s::jsonb) rs on %s',

            -- row_id
            rel_id.schema_name,
            rel_id.name,
            'x',
            'x',

            -- col stmts
            col_stmt,

            -- from relation
            rel_id.schema_name,
            rel_id.name,

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
