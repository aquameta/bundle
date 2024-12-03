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

    for r in select * from ditty._get_commit_rows(_commit_id) order by _position desc loop
        if r.row_id is null then raise exception '_delete_checkout(): row_id is null'; end if;

        pk_comparison_stmt := meta._pk_stmt(r.row_id, '%1$I::text = %2$L');
        stmt := format ('delete from %I.%I where %s',
            (r.row_id).schema_name,
            (r.row_id).relation_name,
            pk_comparison_stmt);
        -- raise notice 'delete_checkout() stmt: %', stmt;
        execute stmt;
    end loop;

    raise notice '_delete_checkout() ... %s', ditty.clock_diff(start_time);
end;
$$ language plpgsql;

create or replace function delete_checkout( repository_name text ) returns void as $$
    select ditty._delete_checkout(ditty.checkout_commit_id(repository_name));
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
    if not ditty._commit_exists(_commit_id) then
        raise exception 'Commit with id % does not exist.', _commit_id;
    end if;

    -- propagate vars
    select r.id, r.name, r.head_commit_id, r.checkout_commit_id, c.message
    from ditty.commit c
        join ditty.repository r on r.id = c.repository_id
    where c.id = _commit_id
    into _repository_id, repository_name, _head_commit_id, _checkout_commit_id, commit_message;

    -- repo has no uncommitted changes
    if ditty._repository_has_uncommitted_changes(_repository_id) then
        raise exception 'Repository % has uncommitted changes, checkout() cannot be performed.', ditty._repository_name(_repository_id);
    end if;

    -- if repo is already checked out, then delete it
    -- TODO: instead of just deleting the checkout, do a diff between _commit_id and _checkout_commit_id, and make selective changes
    if _checkout_commit_id is not null then
        perform ditty._delete_checkout(_checkout_commit_id);
    end if;

    -- naive.
    -- TODO: single insert stmt per relation, smart dependency traversing etc

    for commit_row in
        select r.row_id, jsonb_object_agg((f.field_id).column_name, f.value_hash) as fields
        from ditty._get_commit_rows(_commit_id) r
            join ditty._get_commit_fields(_commit_id) f on (f.field_id)::meta.row_id = r.row_id
            -- TODO: undisable hash
            -- join ditty.blob b on f.value_hash = b.hash
        group by r.row_id, r._position
        order by r._position
    loop
        -- raise notice 'CHECKING OUT ROW: % ===> %', (commit_row.row_id)::text, (commit_row.fields)::text;
        perform ditty._checkout_row(commit_row.row_id, commit_row.fields);
    end loop;

    raise notice '_checkout() ... %s', ditty.clock_diff(start_time);
    return format('Commit %s was checked out.', _commit_id);
end
$$ language plpgsql;


create or replace function checkout( repository_name text ) returns void as $$
declare
    _head_commit_id uuid;
    _repository_id uuid;
begin
    _repository_id := ditty.repository_id(repository_name);
    if _repository_id is null then
        raise notice 'Repository % does not exist.', repository_name;
    end if;

    if not ditty._repository_has_commits(_repository_id) then
        raise notice 'Repository % has no commits.', repository_name;
    end if;

    _head_commit_id = ditty._head_commit_id(_repository_id);
    if _repository_id is null then
        raise notice 'Repository with name % has no head_commit_id.', repository_name;
    end if;

    perform ditty._checkout(_head_commit_id);
end
$$ language plpgsql;


--
-- _checkout_row()
--
-- Checks out a single row given a row_id and a jsonb fields object

create or replace function _checkout_row( row_id meta.row_id, fields jsonb) returns void as $$
declare
    stmt text;
    cols text[] := '{}';
    vals text[] := '{}';
    row record;
begin
    for row in select key, value from jsonb_each_text(fields) loop
        cols := cols || row.key;
        vals := vals || row.value;
    end loop;

    stmt := format('insert into %I.%I (%s) values (%s)',
        (row_id).schema_name,
        (row_id).relation_name,
        -- cols stmt
        (select array_to_string(
            array_agg(quote_ident(col)), ', ')
        from unnest(cols) as col),
        -- vals stmt
        (select array_to_string(
            array_agg(
                case when val is null then 'null' else quote_literal(val::text) end
            ), ', ')
        from unnest(vals) as val)
    );

    execute stmt;

    return;
end
$$ language plpgsql;

