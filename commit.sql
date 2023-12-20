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
        first_commit boolean := false;
    begin
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

        -- create the commit
        insert into delta.commit (
            repository_id,
            message,
            author_name,
            author_email,
            parent_id
        ) values (
            _repository_id,
            message,
            author_name,
            author_email,
            parent_commit_id
        )
        returning id into new_commit_id;

        -- blob
        insert into delta.blob (value)
        select (jsonb_each(value)).value as v from delta.stage_row_added;

        -- commit_field_added
        insert into delta.commit_field_added (commit_id, field_id, value_hash)
        select new_commit_id, meta.field_id(fields.row_id, fields.key), fields.hash
        from (
            select row_id, (jsonb_each(value)).*, public.digest((jsonb_each(value)).value::text, 'sha256') as hash from delta.stage_row_added
        ) fields;

        -- commit_row_added
        insert into delta.commit_row_added (commit_id, row_id, position)
        select new_commit_id, row_id, 0 from delta.stage_row_added where repository_id = _repository_id;
        delete from delta.stage_row_added where repository_id = _repository_id;

        -- commit_row_deleted
        insert into delta.commit_row_deleted (commit_id, row_id, position)
        select new_commit_id, row_id, 0 from delta.stage_row_deleted where repository_id = _repository_id;
        delete from delta.stage_row_deleted where repository_id = _repository_id;

    /*
        insert into commit_row_deleted
        insert into commit_field_changed
        insert into commit_field_*
        insert into blob
    */

        -- update head pointer, checkout pointer
        update delta.repository set head_commit_id = new_commit_id, checkout_commit_id = new_commit_id where id=_repository_id;

        execute format ('refresh materialized view concurrently delta.head_commit_row');
        execute format ('refresh materialized view concurrently delta.head_commit_field');

        -- TODO: unset search_path

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


--
-- topological_sort
-- ganked from https://wiki.postgresql.org/wiki/Topological_sort
--

CREATE OR REPLACE FUNCTION topological_sort(_nodes int[], _edges public.hstore)
RETURNS int[]
LANGUAGE plpgsql
AS $$
DECLARE
_L int[];
_S int[];
_n int;
_all_ms text[];
_m text;
_n_m_edges int[];
BEGIN
_L := '{}';
_S := ARRAY(
    SELECT u.node
    FROM unnest(_nodes) u(node)
    WHERE (_edges->(u.node::text)) IS NULL
);
IF array_length(_S, 1) IS NULL THEN
    RAISE EXCEPTION 'no nodes with no incoming edges in input';
END IF;

WHILE array_length(_S, 1) IS NOT NULL LOOP
    _n := _S[1];
    _S := _S[2:];

    _L := array_append(_L, _n);
    _all_ms := ARRAY(
        SELECT each.key
        FROM each(_edges)
        WHERE (each.value)::int[] @> ARRAY[_n]
    );
    FOREACH _m IN ARRAY _all_ms LOOP
        _n_m_edges := (_edges->_m)::int[];
        IF _n_m_edges = ARRAY[_n] THEN
            _S := array_append(_s, _m::int);
            _edges := _edges - _m;
        ELSE
            _edges := _edges || public.hstore(_m, array_remove(_n_m_edges, _n)::text);
        END IF;
    END LOOP;
END LOOP;
IF _edges <> '' THEN
    RAISE EXCEPTION 'input graph contains cycles';
END IF;
RETURN _L;
END
$$;
