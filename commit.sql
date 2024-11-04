------------------------------------------------------------------------------
-- COMMIT
------------------------------------------------------------------------------

--
-- get_commit_ancestry()
--

create type _commit_ancestry as( commit_id uuid, position integer );
create or replace function _get_commit_ancestry( _commit_id uuid ) returns setof _commit_ancestry as $$
    with recursive parent as (
        select c.id, c.parent_id, 1 as position from delta.commit c where c.id=_commit_id
        union
        select c.id, c.parent_id, p.position + 1 from delta.commit c join parent p on c.id = p.parent_id
    ) select id, position from parent
$$ language sql;


--
-- commit()
--

create or replace function _commit(
    _repository_id uuid,
    _message text,
    _author_name text,
    _author_email text,
    parent_commit_id uuid default null
) returns uuid as $$
    declare
        new_commit_id uuid;
        parent_commit_id uuid;
        _jsonb_rows jsonb;
        _jsonb_fields jsonb := '{}';
        stage_row_relations meta.relation_id[];
        r record;

        first_commit boolean := false;
        start_time timestamp;
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
                raise debug 'First commit!';
                first_commit := true;
            end if;
        end if;

        raise debug 'commit()';
        raise debug '  - parent_commit_id: %', parent_commit_id;

        -- blob
        /*
        raise debug '  - Inserting blobs @ % ...', clock_timestamp() - start_time;
        insert into delta.blob (value)
        select distinct (jsonb_each(sra.value)).value
        from delta._get_stage_rows_to_add(_repository_id); -- FIXME
        */

        --
        -- create _jsonb_rows
        --

        raise debug '  - Creating _jsonb_rows @ % ...', clock_timestamp() - start_time;
        if parent_commit_id is null then
            -- first commit
            _jsonb_rows := (select stage_rows_to_add from delta.repository where id = _repository_id);
        else
            -- modify parent commit, adding repo.stage_rows_to_add
            _jsonb_rows := (
                select delta._get_commit_jsonb_rows(parent_commit_id)
                    || repository.stage_rows_to_add
                from delta.repository
                where id = _repository_id
            );

            -- remove rows
            _jsonb_rows := (
                select jsonb_agg(a.elem)
                from jsonb_array_elements(_jsonb_rows) a(elem)
                    left join jsonb_array_elements((
                        select repository.stage_rows_to_remove
                        from delta.repository
                        where id = _repository_id
                    )) b(elem) on a.elem = b.elem
                where b.elem is null
            );
        end if;

        -- topo sort relations
        raise debug '  - Computing topological relation sort @ % ...', clock_timestamp() - start_time;
        stage_row_relations := delta._topological_sort_relations(delta._get_rowset_relations(_jsonb_rows));
        raise notice 'stage_row_relations: %', stage_row_relations;

		-- sort rows
		_jsonb_rows := (
			select jsonb_agg(rr)
			from (
				select elem.r::jsonb as rr
				from jsonb_array_elements(_jsonb_rows) elem(r)
				order by array_position(stage_row_relations, elem.r::meta.relation_id)
			) sorted_rows
		);

        raise notice 'jsonb_rows: %', jsonb_pretty(_jsonb_rows);

        --
        -- create _jsonb_fields
        --

        /*
        steps:

        1. If there is a parent commit, set _jsonb_fields to c.jsonb_fields
           plus r.stage_fields_to_change.  Old fields plus their changes.

        2. For all stage_rows_to_add, grab their fields objects and add them
           to the _jsonb_fields.

        3. For all stage_rows_to_remove, remove their fields object from
           _jsonb_fields.
        */

        if parent_commit_id is not null then
            -- not first commit, grab previous fields and apply fields_to_change
            _jsonb_fields := (
                select delta._get_commit_jsonb_fields(parent_commit_id)
                    -- || delta._get_stage_fields_to_change(_repository_id): FIXME doesn't work.
                );
        end if;

        -- slow crappy way.  optimize failure in db._get_db_rowset_fields_obj()
        for r in
            select rep.id, elem.row_id::meta.row_id as row_id
            from delta.repository rep,
                lateral jsonb_array_elements_text(rep.stage_rows_to_add) elem(row_id)
            where rep.id=_repository_id
        loop
            _jsonb_fields := _jsonb_fields || jsonb_build_object(
                r.row_id::text,
                delta._get_db_row_fields_obj(r.row_id)
            );
        end loop;

        raise notice 'jsonb_fields: %', jsonb_pretty(_jsonb_fields);

        -- create commit, without jsonb_fields object, to be set later
        insert into delta.commit (
            repository_id,
            parent_id,
            -- commit_time, default now(), also not in function sig
            message,
            author_name,
            author_email,
            jsonb_rows,
            jsonb_fields
        ) values (
            _repository_id,
            parent_commit_id,
            _message,
            _author_name,
            _author_email,
            _jsonb_rows,
            _jsonb_fields
        ) returning id into new_commit_id;


        /*
        _jsonb_fields := _jsonb_fields || (
            select delta._get_db_rowset_fields_obj(r.stage_rows_to_add)
            from delta.repository r
            where r.id = _repository_id
        );
        */


        -- clear this repo's stage
        perform delta._empty_stage(_repository_id);

        raise debug '  - New commit with id %', new_commit_id;


        -- update head pointer, checkout pointer
        update delta.repository set head_commit_id = new_commit_id, checkout_commit_id = new_commit_id where id=_repository_id;

        -- TODO: unset search_path

        raise debug '  - Done @ %', clock_timestamp() - start_time;
        return new_commit_id;
    end;
$$ language plpgsql;


create or replace function commit(
    repository_name text,
    message text,
    author_name text,
    author_email text,
    parent_commit_id uuid default null
) returns uuid as $$
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
create or replace function delta._topological_sort_relations( _relations meta.relation_id[] )
returns meta.relation_id[] as $$
declare
    start_time timestamp := clock_timestamp();
    edges delta.schema_edge[];
    s meta.relation_id[];
    l meta.relation_id[] = '{}';
    n meta.relation_id;
    m meta.relation_id;
    m_edge delta.schema_edge;
begin
    -- edges
    raise debug '  - Building edges @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct row(r,meta.relation_id(fk.to_schema_name, fk.to_table_name))::delta.schema_edge)
    from meta.foreign_key fk
        join unnest(_relations) r on r.schema_name = fk.schema_name and r.name = fk.table_name
    into edges;


    -- s
    raise debug '  - Building s @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct srr)
    from unnest(_relations) as srr
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
        from delta.stage_row_to_add
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
