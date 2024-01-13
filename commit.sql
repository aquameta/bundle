------------------------------------------------------------------------------
-- COMMIT
------------------------------------------------------------------------------

--
-- commit_ancestry()
--

create type _commit_ancestry as( commit_id uuid, position integer );
create or replace function _commit_ancestry( _commit_id uuid ) returns setof _commit_ancestry as $$
    with recursive parent as (
        select c.id, c.parent_id, 1 as position from delta.commit c where c.id=_commit_id
        union
        select c.id, c.parent_id, p.position + 1 from delta.commit c join parent p on c.id = p.parent_id
    ) select id, position from parent
$$ language sql;


--
-- _commit_exists()
--

create function _commit_exists(commit_id uuid) returns boolean as $$
    select exists (select 1 from delta.commit where id=commit_id);
$$ language sql;


--
-- commit()
--

create function _commit(
    _repository_id uuid,
    message text,
    author_name text,
    author_email text,
    parent_commit_id uuid default null
) returns uuid as $$
    declare
        new_commit_id uuid;
        parent_commit_id uuid;
        manifest jsonb := '{}';
        first_commit boolean := false;
        start_time timestamp;
        stage_row_relations meta.relation_id[];
    begin
        start_time := clock_timestamp();

        -- repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- if no parent_commit_id is supplied, use head pointer
        if parent_commit_id is null then
            select head_commit_id from delta.repository where id = _repository_id into parent_commit_id;
        end if;

        -- if repository has no head commit and one is not supplied, either this is the first
        -- commit, or there is a problem
        if parent_commit_id is null then
            if delta._repository_has_commits(_repository_id) then
                raise exception 'No parent_commit_id supplied, and repository''s head_commit_id is null.  Please specify a parent commit_id for this commit.';
            else
                raise notice 'First commit!';
                first_commit := true;
            end if;
        end if;

        raise notice 'commit()';


/*
        manifest := select jsonb_agg(
            jsonb_build_object(
                'schema_name', (s.row_id).schema_name,
                'relation_name', (s.row_id).relation_name,
                'pk_column_name', (s.row_id).pk_column_names,
                'columns', (s.row_id).schema_name,
        ) from delta.stage_rows(_repository_id) s;
*/


        -- create the commit
        insert into delta.commit (
            repository_id,
            parent_id,
            manifest,
            message,
            author_name,
            author_email
        ) values (
            _repository_id,
            parent_commit_id,
            manifest,
            message,
            author_name,
            author_email

        )
        returning id into new_commit_id;


        -- blob
        /*
        raise notice '  - Inserting blobs @ % ...', clock_timestamp() - start_time;
        insert into delta.blob (value)
        select distinct (jsonb_each(sra.value)).value from delta.stage_row_added sra;
        */


        -- commit_field_changed
        /*
        raise notice '  - Inserting commit_fields @ % ...', clock_timestamp() - start_time;
        insert into delta.commit_field_changed (commit_id, field_id, value_hash, change_type)
        select new_commit_id, meta.field_id(fields.row_id, fields.key), fields.hash, 'add'
        from (
            select row_id, (jsonb_each_text(value)).*, public.digest((jsonb_each_text(value)).value::text, 'sha256') as hash from delta.stage_row_added
        ) fields;
        */


        -- topo sort
        raise notice '  - Computing topological relation sort @ % ...', clock_timestamp() - start_time;
        stage_row_relations := delta.topological_sort_stage(_repository_id);


        -- commit_row_added
        raise notice '  - Inserting commit_row_added @ % ...', clock_timestamp() - start_time;
        insert into delta.commit_row_added (commit_id, row_id, position)
        select new_commit_id, row_id, row_number() over (order by array_position(stage_row_relations, row_id::meta.relation_id))
        from delta.stage_row_added
        where repository_id = _repository_id;

        delete from delta.stage_row_added where repository_id = _repository_id;


        -- commit_row_deleted
        raise notice '  - Inserting commit_row_deleted @ % ...', clock_timestamp() - start_time;
        insert into delta.commit_row_deleted (commit_id, row_id, position)
        select new_commit_id, row_id, row_number() over (order by array_position(stage_row_relations, row_id::meta.relation_id))
        from delta.stage_row_deleted
        where repository_id = _repository_id;

        delete from delta.stage_row_deleted where repository_id = _repository_id;


    /*
        insert into commit_field_changed
        insert into commit_field_*
    */

        -- update head pointer, checkout pointer
        update delta.repository set head_commit_id = new_commit_id, checkout_commit_id = new_commit_id where id=_repository_id;

        raise notice '  - Refreshing head_commit_row @ % ...', clock_timestamp() - start_time;
        execute format ('refresh materialized view delta.head_commit_row');

        raise notice '  - Refreshing head_commit_field @ % ...', clock_timestamp() - start_time;
        execute format ('refresh materialized view delta.head_commit_field');

        -- TODO: unset search_path

        raise notice '  - Done @ %', clock_timestamp() - start_time;
        return new_commit_id;
    end;
$$ language plpgsql;


create or replace function commit(
    repository_name text,
    message text,
    author_name text,
    author_email text,
    parent_commit_id uuid default null
)
returns uuid as $$
begin
    if not delta.repository_exists(repository_name) then
        raise exception 'Repository with name % does not exists', repository_name;
    end if;
    return delta._commit(delta.repository_id(repository_name), message, author_name, author_email, parent_commit_id);
end;
$$ language plpgsql;



/*
Objective:

- row-order for checkout
- external dependencies and the rows/bundles that satisfy them if any


Approach:
- for each row:
    - if is_meta(row_id)
        - Use pg_depend to get the list of objects this object depends on
        - Are those rows in this bundle?
    - else (it's data)
        - containing table, columns, and foreign keys
            - tables: select distinct row_id::meta.relation_id
            - columns: select .....?
        - fk_dependency_rows:  What rows does it foreign key to?
            - boolean external: Are those rows in this bundle?
                - internal: affects order
                - external: affects commit dependencies
            - boolean deferrable: Is the foreign key deferrable?
            - on_delete: cascade, set null, set default, do nothing
1. Get the full list of dependant rows that rows on the stage have.  That could include:
  - data: rows that these rows foreign key to
  - data-tables: the tables and columns that the rows are in
  - objects: for any meta stuff, the pg_depend object(s) that it depends on

2. Determine whether or not this is an external dependency
  - is the dependency in this bundle?
    - no:
      - data: row foreign-keys to row not in this bundle
      - data-tables: this row is in a table created by some other bundle, if any.  Which bundle?
      - objects: a DDL object (non-table?) that
    - yes

*/

create type delta.schema_edge as (from_relation_id meta.relation_id, to_relation_id meta.relation_id);
create or replace function delta.topological_sort_stage( _repository_id uuid ) returns meta.relation_id[] as $$
declare
    start_time timestamp := clock_timestamp();
    stage_row_relations meta.relation_id[];
    edges delta.schema_edge[];
    s meta.relation_id[];
    l meta.relation_id[] = '{}';
    n meta.relation_id;
    m meta.relation_id;
    m_edge delta.schema_edge;
begin
    -- stage_row_relations
    raise debug '  - Building stage_row_relations @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct row_id::meta.relation_id)
        from delta.stage_row_added
        where repository_id =  _repository_id
    into stage_row_relations;


    -- edges
    raise debug '  - Building edges @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct row(srr,meta.relation_id(fk.to_schema_name, fk.to_table_name))::delta.schema_edge)
    from meta.foreign_key fk
        join unnest(stage_row_relations) srr on srr.schema_name = fk.schema_name and srr.name = fk.table_name
    into edges;


    -- s
    raise debug '  - Building s @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct srr)
    from unnest(stage_row_relations) as srr
       left join unnest(edges) as edge on srr = edge.to_relation_id
    where edge.to_relation_id is null
    into s;


    -- topo sort
    raise debug '  - Topological sort @ % ...', clock_timestamp() - start_time;
    while array_length(s, 1) > 0 loop
        n := s[1];
        s := s[2:];
        l := array_append(l, n);

        -- for each node m that n points to
        for m_edge in ( select * from unnest(edges) e where e.from_relation_id = n )
        loop
            m := m_edge.to_relation_id;
            edges := array_remove(edges, m_edge);
            if (select count(*) from unnest(edges) edge where edge.to_relation_id = m) < 1 then
                s := array_append(s, m);
            end if;
        end loop;
    end loop;
    if array_length(edges, 1) > 0 then
        raise exception 'Input graph contains cycles: %', edges;
        -- TODO: break cycles if possible w/ deferrable fks?
    end if;
    return l;
end
$$ language plpgsql;




/*

failed attempt #20:

create or replace function analyze_stage_deps( _repository_id uuid ) returns void as $$
declare
    start_time timestamp := clock_timestamp();

    stage_row_relations jsonb;
    r record;

    s jsonb = '[]';
    key text;
    value jsonb;
begin
    -- stage_row relations as jsonb object keys, value is empty array
    raise notice '  - Building stage_row_relations @ % ...', clock_timestamp() - start_time;
    select distinct jsonb_object_agg(row_id::meta.relation_id::text, '[]'::jsonb)
        from delta.stage_row_added
        where repository_id =  _repository_id
    into stage_row_relations;

    -- Add a foreign key object to the value array of stage_row_relations
    raise notice '  - Building stage_row_fts @ % ...', clock_timestamp() - start_time;
    for r in
    select u.rel_key as rel_key, fk.from_column_ids, fk.to_column_ids
        from jsonb_object_keys(stage_row_relations) u(rel_key)
        left join meta.foreign_key fk on u.rel_key = fk.table_id::text
    loop
        -- if this relation doesn't foreign key to anything
        if r.from_column_ids is null then
            raise notice '% fks to NOTHING.', r.rel_key;

        -- otherwise add the key to the stage_row_relations obj
        else
            stage_row_relations := jsonb_set(
                stage_row_relations,
                array[r.rel_key],
                stage_row_relations->(r.rel_key) || jsonb_build_object(
                    'relation_id', r.rel_key,
                    'from_column_ids', r.from_column_ids,
                    'to_column_ids', r.to_column_ids,
                    'to_relation_id', (r.to_column_ids[1])::meta.relation_id::text
                )
            );
        end if;
    end loop;

    raise notice 'stage_row_relations: %', jsonb_pretty(stage_row_relations);

    -- build s
    for r in
        select srr.relation_id as from_relation_id, to_cols.props->>relation_id as to_relation_id
        from jsonb_object_keys(stage_row_relations) srr(relation_id)
            join jsonb_path_query(stage_row_relations,'$.*.*') to_cols(props)
                on to_cols.props->>'relation_id' = (srr.relation_id)
    loop
        raise notice 'r: %', r;
        raise notice 'r.from_relation_id: %', r.from_relation_id;
        raise notice 'r.to_relation_id: %', r.to_relation_id;

    end loop;

end
$$ language plpgsql;
*/
