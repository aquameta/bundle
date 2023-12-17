------------------------------------------------------------------------------
-- CHECKOUT
------------------------------------------------------------------------------

--
-- checkout_delete()
--

create or replace function _checkout_delete( _commit_id uuid ) returns void as $$
declare
        r record;
        pk_comparison_stmt text;
begin
    -- TODO: check for uncommited changes?
    -- TODO: there's a whole dependency chain to follow here.
    -- TODO: speed this up by grouping by relation, one delete stmt per relation
    -- TODO: set repo.checkout_commit_id to null?  probably.

    for r in select * from delta.commit_rows(_commit_id) loop
        if r.row_id is null then raise exception '_checkout_delete(): row_id is null'; end if;

        pk_comparison_stmt := meta._pk_stmt(r.row_id, '%1$I::text = %2$L::text');
        execute format ('delete from %I.%I where %s',
            (r.row_id).schema_name,
            (r.row_id).relation_name,
            pk_comparison_stmt);
    end loop;
end;
$$ language plpgsql;



--
-- checkout()
--

create function _checkout( _commit_id uuid ) returns text as $$
declare
    _repository_id uuid;
    _head_commit_id uuid;
    _checkout_commit_id uuid;
    repository_name text;
    commit_message text;

    commit_row record;
begin
    -- commit exists
    if not delta._commit_exists(_commit_id) then
        raise exception 'Commit with id % does not exist.', _commit_id;
    end if;

    -- propagate vars
    select r.id, r.name, r.head_commit_id, r.checkout_commit_id, c.message
    from delta.commit c join delta.repository r on r.id = c.repository_id
    where c.id = _commit_id
    into _repository_id, repository_name, _head_commit_id, _checkout_commit_id, commit_message;

    -- repo has no uncommitted changes
    if delta._repository_has_uncommitted_changes(_repository_id) then
        raise exception 'Repository % has uncommited changes, checkout() cannot be performed.', delta.repository_name(_repository_id);
    end if;

    -- if repo is already checked out, then delete it
    -- TODO: instead of just deleting the checkout, do a diff between _commit_id and _checkout_commit_id, and make selective changes
    if _checkout_commit_id is not null then
        perform delta._checkout_delete(_checkout_commit_id);
    end if;

    -- naive.
    -- TODO: single insert stmt per relation, smart dependency traversing etc

    for commit_row in
        select commit_id, row_id from delta.commit_rows(_commit_id) r
            -- join delta.commit_fields(_commit_id) f on (f.field_id)::meta.row_id = r.row_id
        -- group by r.row_id, commit_id
    loop
        -- raise notice 'CHECKING OUT ROW: %', commit_row;
        -- raise notice 'CHECKING OUT ROW_ID: %', commit_row.row_id;
        perform delta._checkout_row(commit_row.row_id);
    end loop;

    return format('Commit %s was checked out.', _commit_id);
end
$$ language plpgsql;


create function _checkout_row( row_id meta.row_id) returns void as $$
declare
    insert_stmt text;
begin
    raise notice '_checkout_row( % )', row_id;
    return;
end
$$ language plpgsql;
