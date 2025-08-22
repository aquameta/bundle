------------------------------------------------------------------------------
-- CHECKOUT
------------------------------------------------------------------------------

--
-- delete_checkout()
--

create or replace function _delete_checkout( _commit_id uuid ) returns void as $$
declare
    r record;
    pk_comparison_stmt text;
    stmt text;
    start_time timestamp := clock_timestamp();
begin
    -- TODO: check for uncommitted changes?
    -- TODO: there's a whole dependency chain to follow here.
    -- TODO: speed this up by grouping by relation, one delete stmt per relation

    for r in select * from bundle._get_commit_rows(_commit_id) order by _position desc loop
        if r.row_id is null then raise exception '_delete_checkout(): row_id is null'; end if;

        pk_comparison_stmt := meta._pk_stmt(r.row_id, '%1$I::text = %2$L');
        stmt := format ('delete from %I.%I where %s',
            (r.row_id).schema_name,
            (r.row_id).relation_name,
            pk_comparison_stmt);
        -- raise notice 'delete_checkout() stmt: %', stmt;
        execute stmt;
    end loop;

    raise notice '_delete_checkout() ... %s', bundle.clock_diff(start_time);
end;
$$ language plpgsql;

create or replace function delete_checkout( repository_name text ) returns void as $$
    select bundle._delete_checkout(bundle.checkout_commit_id(repository_name));
$$ language sql;


--
-- checkout()
--

create or replace function _checkout( _commit_id uuid ) returns text as $$
declare
    _repository_id uuid;
    _head_commit_id uuid;
    _checkout_commit_id uuid;
    repository_name text;
    commit_message text;

    commit_row record;
    start_time timestamp := clock_timestamp();
begin
    -- commit exists
    if not bundle._commit_exists(_commit_id) then
        raise exception 'Commit with id % does not exist.', _commit_id;
    end if;

    -- propagate vars
    select r.id, r.name, r.head_commit_id, r.checkout_commit_id, c.message
    from bundle.commit c
        join bundle.repository r on r.id = c.repository_id
    where c.id = _commit_id
    into _repository_id, repository_name, _head_commit_id, _checkout_commit_id, commit_message;

    -- repo has no uncommitted changes
    if bundle._repository_has_uncommitted_changes(_repository_id) then
        raise exception 'Repository % has uncommitted changes, checkout() cannot be performed.', bundle._repository_name(_repository_id);
    end if;

    -- naive.
    -- TODO: single insert stmt per relation, smart dependency traversing etc
    for commit_row in
        select r.row_id, jsonb_object_agg(f.field_id->>'column_name', f.value_hash) as fields
        from bundle._get_commit_rows(_commit_id) r
            join bundle._get_commit_fields(_commit_id) f on meta.field_id_to_row_id(f.field_id) = r.row_id
        group by r.row_id, r._position
        order by r._position
    loop
        -- raise notice 'CHECKING OUT ROW: % ===> %', (commit_row.row_id)::text, (commit_row.fields)::text;
        perform bundle._checkout_row(commit_row.row_id, commit_row.fields);
    end loop;

    raise notice '_checkout() ... %s', bundle.clock_diff(start_time);
    return format('Commit %s was checked out.', _commit_id);
end
$$ language plpgsql;


create or replace function checkout( repository_name text ) returns void as $$
declare
    _head_commit_id uuid;
    _repository_id uuid;
begin
    _repository_id := bundle.repository_id(repository_name);
    if _repository_id is null then
        raise notice 'Repository % does not exist.', repository_name;
    end if;

    if not bundle._repository_has_commits(_repository_id) then
        raise notice 'Repository % has no commits.', repository_name;
    end if;

    _head_commit_id = bundle._head_commit_id(_repository_id);
    if _repository_id is null then
        raise notice 'Repository with name % has no head_commit_id.', repository_name;
    end if;

    perform bundle._checkout(_head_commit_id);
end
$$ language plpgsql;


--
-- _checkout_row()
--
-- Checks out a single row given a row_id and a jsonb fields object
-- Uses jsonb_populate_record() for proper type conversion
-- Optional upsert parameter for conflict handling

create or replace function _checkout_row( row_id meta.row_id, fields jsonb, upsert boolean default false) returns void as $$
declare
    stmt text;
    unhashed_fields jsonb = '{}';
    field_key text;
    field_value text;
    schema_name text;
    table_name text;
    cols text;
    pk_columns text[];
    conflict_clause text := '';
begin
    -- Extract schema and table names
    schema_name := row_id->>'schema_name';
    table_name := row_id->>'relation_name';

    raise debug '_checkout_row(): fields: %', fields;

    -- Unhash all field values to build the JSONB object
    for field_key, field_value in select key, value from jsonb_each_text(fields) loop
        raise debug '   _checkout_row(): field %: %', field_key, field_value;
        unhashed_fields := unhashed_fields || jsonb_build_object(field_key, bundle.unhash(field_value));
    end loop;

    raise debug '_checkout_row(): unhashed fields: %', unhashed_fields;

    -- Get column list from JSONB keys
    select string_agg(quote_ident(key), ', ') into cols
    from jsonb_object_keys(unhashed_fields) as key;

    -- Build conflict clause if upsert is requested
    if upsert then
        -- Get PK column names directly from row_id
        select array(select jsonb_array_elements_text(row_id->'pk_column_names')) into pk_columns;

        if pk_columns is not null and array_length(pk_columns, 1) > 0 then
            conflict_clause := format(
                ' on conflict (%s) do update set %s',
                array_to_string(array(select quote_ident(col) from unnest(pk_columns) col), ', '),
                -- Build UPDATE SET clause (excluding PK columns)
                (select string_agg(
                    format('%I = excluded.%I', col, col),
                    ', '
                )
                from jsonb_object_keys(unhashed_fields) col
                where not (col = any(pk_columns)))
            );
        else
            raise warning '_checkout_row(): No primary key found in row_id for %.%, using INSERT only', schema_name, table_name;
        end if;
    end if;

    -- Build statement with optional conflict clause
    stmt := format($sql$
        insert into %I.%I (%s)
        select %s from jsonb_populate_record(null::%I.%I, %L)%s
    $sql$,
        schema_name,
        table_name,
        cols,
        cols,
        schema_name,
        table_name,
        unhashed_fields,
        conflict_clause
    );

    raise debug '    _checkout_row(): stmt: %', stmt;

    execute stmt;
    return;
exception
    when others then
        raise exception '_checkout_row() failed for %.%: %',
            schema_name, table_name, SQLERRM;
end
$$ language plpgsql;
