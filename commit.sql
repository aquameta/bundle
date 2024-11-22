------------------------------------------------------------------------------
-- COMMIT
------------------------------------------------------------------------------

--
-- get_commit_ancestry()
--

create type _commit_ancestor as( commit_id uuid, position integer );
create or replace function _get_commit_ancestry( _commit_id uuid ) returns setof _commit_ancestor as $$
    with recursive parent as (
        select c.id, c.parent_id, 1 as position from ditty.commit c where c.id=_commit_id
        union
        select c.id, c.parent_id, p.position + 1 from ditty.commit c join parent p on c.id = p.parent_id
    ) select id, position from parent
$$ language sql;


create or replace function __commit_stage_blobs( _repository_id uuid, new_commit_id uuid, parent_commit_id uuid ) returns void as $$
begin
        --
        -- blob
        --

        /*
        raise debug '  - Inserting blobs @ % ...', clock_diff(start_time);

        ultimately we want a list of values to add to the blob table
        1. get relations present in stage_rows_to_add
        2. get columns for each relation
        3. for each relation join stage_rows_to_add on pks=pks
        4.     for every row also in stage_rows_to_add

        insert into ditty.blob (value)
        select distinct (jsonb_each(sra.value)).value
        from ditty._get_stage_rows_to_add(_repository_id); -- FIXME
        */
end;
$$ language plpgsql;


create or replace function __commit_stage_rows( _repository_id uuid, new_commit_id uuid, parent_commit_id uuid ) returns void as $$
declare
    stage_row_relations meta.relation_id[];
begin
    -- if first commit:
    -- jsonb_rows is only stage_rows_to_add

    if parent_commit_id is null then
        update ditty.commit set jsonb_rows = stage_rows_to_add 
        from ditty.repository
        where repository.id=_repository_id and commit.id = new_commit_id;
        -- TODO: sort

    -- else not first commit:
    -- jsonb_rows is parent commit's rows + stage_rows_to_add - stage_rows_to_remove

    else
        update ditty.commit set jsonb_rows = parent_rows
        from (
            select jsonb_rows || stage_rows_to_add as parent_rows
            from ditty.commit
                join ditty.repository on commit.repository_id = repository.id
            where commit.id = parent_commit_id
        )
        where commit.id = new_commit_id;

        -- get topo sorted relations
        select ditty._topological_sort_relations(ditty._get_rowset_relations(jsonb_rows))
        from ditty.commit
        where id=new_commit_id
        into stage_row_relations;

        raise notice '    - stage_row_relations: %', stage_row_relations;

        -- remove rows
        update ditty.commit
        set jsonb_rows = coalesce(( -- catch nulls
            select jsonb_agg(elem) from (
                select elem from jsonb_array_elements_text(jsonb_rows) a(elem)
                left join (
                    select jsonb_array_elements_text(stage_rows_to_remove) from ditty.repository where id=_repository_id
                ) x(rem) on x.rem = a.elem
                where x.rem is null
                order by array_position(stage_row_relations, elem::meta.row_id::meta.relation_id)
            )
        ), '[]'::jsonb)
        where id = new_commit_id;
    end if;
end;
$$ language plpgsql;

--
-- __commit_stage_fields
--

create or replace function __commit_stage_fields( _repository_id uuid, new_commit_id uuid, parent_commit_id uuid ) returns void as $$
declare
    rec record;
begin

    /*
    1. Set commit.jsonb_fields to repo.rows_to_add.fields
    2. If this is not the first commit:
        a) jsonb_fields += parent_commit.jsonb_fields - repo.rows_to_remove.fields
        b) Merge in repo.fields_to_change
    */

        /*
         * FIRST COMMIT
         */

    -- apply fields for rows_to_add
    -- optimize attempt failure in db._get_db_rowset_fields_obj()

    with rows as (
        select jsonb_array_elements_text(c.jsonb_rows) as row_id
        from ditty.commit c
        where id=new_commit_id
    ),
    fields as (
        select
            jsonb_object_agg(
                row_id,
                ditty._get_db_row_fields_obj(row_id::meta.row_id) -- can we go even faster??
            ) as fields_obj
        from rows
    )
    update ditty.commit set jsonb_fields = coalesce(fields.fields_obj, '{}') -- FIXME coalesce??
    from fields
    where commit.id=new_commit_id;

    if parent_commit_id is not null then
        /*
         * NOT FIRST COMMIT
         */

        --
        -- parent commit fields - stage_rows_to_remove.fields
        --

        -- raise notice '    - applying (parent_commit - stage_rows_to_remove) fields @ % ...', ditty.clock_diff(start_time);
        update ditty.commit
        set jsonb_fields = jsonb_fields || parent_commit.parent_minus_removed_fields
        from (
            select jsonb_fields - (stage_rows_to_remove::text) as parent_minus_removed_fields
            from ditty.commit c
                join ditty.repository r on c.repository_id = r.id
            where c.id = parent_commit_id
        ) parent_commit
        where id = new_commit_id;

        --
        -- fields_to_change
        --


		with fields as (
			select
				field_text::meta.field_id::meta.row_id as row_id,
				jsonb_object_agg(
					(field_text::meta.field_id).column_name,
					meta.field_id_literal_value(field_text::meta.field_id)
				) as fields_obj
			from ditty.repository
				cross join lateral jsonb_array_elements_text(stage_fields_to_change) field_text
			where id = _repository_id
			group by 1
		),
		fields_obj as (
			select jsonb_object_agg(row_id::text, fields_obj) as obj from fields
        )
        update ditty.commit set jsonb_fields = ditty.jsonb_merge_recurse(
            jsonb_fields,
            fields_obj.obj
		)
		from fields_obj
        where commit.id = new_commit_id;

    end if;
end;
$$ language plpgsql;

 
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
    _jsonb_rows jsonb := '[]';
--    _jsonb_fields jsonb := '{}';
--    _jsonb_fields_patch jsonb := '{}';
    first_commit boolean := false;
    start_time timestamp;
begin
    raise notice 'commit()';

    start_time := clock_timestamp();

    -- repository exists
    if not ditty._repository_exists(_repository_id) then
        raise exception 'Repository with id % does not exist.', _repository_id;
    end if;

    -- if no parent_commit_id is supplied, use head pointer
    if parent_commit_id is null then
        select head_commit_id from ditty.repository where id = _repository_id into parent_commit_id;
    end if;

    -- if repository has no head commit and one is not supplied, either this is the first
    -- commit, or there is a problem
    if parent_commit_id is null then
        if ditty._repository_has_commits(_repository_id) then
            raise exception 'No parent_commit_id supplied, and repository''s head_commit_id is null.  Please specify a parent commit_id for this commit.';
        else
            raise notice 'First commit!';
            first_commit := true;
        end if;
    end if;

    raise notice '  - parent_commit_id: %', parent_commit_id;

    -- create commit, without jsonb_fields object, to be set later
    raise notice '  - Creating commit @ %', ditty.clock_diff(start_time);
    insert into ditty.commit (
        repository_id,
        parent_id,
        message,
        author_name,
        author_email
    ) values (
        _repository_id,
        parent_commit_id,
        _message,
        _author_name,
        _author_email
    ) returning id into new_commit_id;

    raise notice '  - New commit with id %', new_commit_id;

    raise notice '    - stage_blobs() @ %', ditty.clock_diff(start_time);
    perform ditty.__commit_stage_blobs(_repository_id, new_commit_id, parent_commit_id);

    raise notice '    - stage_rows() @ %', ditty.clock_diff(start_time);
    perform ditty.__commit_stage_rows(_repository_id, new_commit_id, parent_commit_id);

    raise notice '    - stage_fields() @ %', ditty.clock_diff(start_time);
    perform ditty.__commit_stage_fields(_repository_id, new_commit_id, parent_commit_id);

--    return new_commit_id;

    -- clear this repo's stage
    perform ditty._empty_stage(_repository_id);


    -- update head pointer, checkout pointer
    update ditty.repository set head_commit_id = new_commit_id, checkout_commit_id = new_commit_id where id=_repository_id;

    -- TODO: unset search_path

    raise notice '  - Done @ %', ditty.clock_diff(start_time);
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
    if not ditty.repository_exists(repository_name) then
        raise exception 'Repository with name % does not exists', repository_name;
    end if;
    return ditty._commit(ditty.repository_id(repository_name), message, author_name, author_email, parent_commit_id);
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

create type ditty.schema_edge as (from_relation_id meta.relation_id, to_relation_id meta.relation_id);
create or replace function ditty._topological_sort_relations( _relations meta.relation_id[] )
returns meta.relation_id[] as $$
declare
    start_time timestamp := clock_timestamp();
    edges ditty.schema_edge[];
    s meta.relation_id[];
    l meta.relation_id[] = '{}';
    n meta.relation_id;
    m meta.relation_id;
    m_edge ditty.schema_edge;
begin
    -- edges
    raise debug '  - Building edges @ % ...', clock_timestamp() - start_time;
    select array_agg(distinct row(r,meta.relation_id(fk.to_schema_name, fk.to_table_name))::ditty.schema_edge)
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
    return ditty.array_reverse(l);
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
        from ditty.stage_row_to_add
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
