------------------------------------------------------------------------------
-- DB2
-- Functions that depend on stage, etc and need to be created after.
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
