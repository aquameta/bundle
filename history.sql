------------------------------------------------------------------------------
-- HISTORY / TIME TRAVEL functions
--
-- Retrieve historical row/field data from any commit.
------------------------------------------------------------------------------

--
-- _get_jsonb_row_at_commit()
--
-- Returns a single row as JSONB, with column names as keys and unhashed values.
--

create or replace function _get_jsonb_row_at_commit(_commit_id uuid, _row_id meta.row_id)
returns jsonb as $$
declare
    row_fields jsonb;
    result jsonb := '{}';
    col_name text;
    col_hash text;
    col_value text;
begin
    -- look up the row's field hashes from the commit
    select jsonb_fields->(_row_id::text)
    into row_fields
    from bundle.commit
    where id = _commit_id;

    -- row not found in commit
    if row_fields is null then
        return null;
    end if;

    -- unhash each field value
    -- values are stored as to_jsonb(val)::text, so parse back to jsonb
    for col_name, col_hash in select * from jsonb_each_text(row_fields) loop
        col_value := bundle.unhash(col_hash);
        if col_value is not null then
            result := result || jsonb_build_object(col_name, col_value::jsonb);
        else
            result := result || jsonb_build_object(col_name, null);
        end if;
    end loop;

    return result;
end;
$$ language plpgsql stable;


--
-- _get_jsonb_rows_at_commit()
--
-- Returns all rows from a relation at a specific commit as setof jsonb.
--

create or replace function _get_jsonb_rows_at_commit(_commit_id uuid, _relation_id meta.relation_id)
returns setof jsonb as $$
    select bundle._get_jsonb_row_at_commit(_commit_id, row_id)
    from bundle._get_commit_rows(_commit_id, _relation_id);
$$ language sql stable;


--
-- _get_jsonb_field_at_commit()
--
-- Returns a single field value (as text) at a specific commit.
--

create or replace function _get_jsonb_field_at_commit(_commit_id uuid, _field_id meta.field_id)
returns text as $$
declare
    _row_id meta.row_id;
    _column_name text;
    _hash text;
    _value text;
begin
    -- extract row_id and column_name from field_id
    _row_id := meta.field_id_to_row_id(_field_id);
    _column_name := _field_id->>'column_name';

    -- look up the hash
    select jsonb_fields->(_row_id::text)->>_column_name
    into _hash
    from bundle.commit
    where id = _commit_id;

    if _hash is null then
        return null;
    end if;

    -- unhash returns to_jsonb(val)::text, so parse back and extract text
    _value := bundle.unhash(_hash);
    if _value is null then
        return null;
    end if;

    return _value::jsonb #>> '{}';
end;
$$ language plpgsql stable;


------------------------------------------------------------------------------
-- RECORD-RETURNING FUNCTIONS
--
-- Use jsonb_populate_record to return actual table row types.
------------------------------------------------------------------------------

--
-- _get_row_at_commit()
--
-- Returns a single row as an actual record type matching the table structure.
-- Pass null::table_name as the third argument to specify the return type.
--
-- Example:
--   select * from bundle._get_row_at_commit(commit_id, row_id, null::widget.widget);
--

create or replace function _get_row_at_commit(
    _commit_id uuid,
    _row_id meta.row_id,
    _record anyelement
)
returns anyelement as $$
    select jsonb_populate_record(
        _record,
        bundle._get_jsonb_row_at_commit(_commit_id, _row_id)
    );
$$ language sql stable;


--
-- _get_rows_at_commit()
--
-- Returns all rows from a relation at a specific commit as actual records.
-- Pass null::table_name as the third argument to specify the return type.
--
-- Example:
--   select * from bundle._get_rows_at_commit(commit_id, relation_id, null::widget.widget);
--

create or replace function _get_rows_at_commit(
    _commit_id uuid,
    _relation_id meta.relation_id,
    _record anyelement
)
returns setof anyelement as $$
    select jsonb_populate_record(
        _record,
        bundle._get_jsonb_row_at_commit(_commit_id, row_id)
    )
    from bundle._get_commit_rows(_commit_id, _relation_id);
$$ language sql stable;


------------------------------------------------------------------------------
-- PUBLIC API
--
-- User-friendly functions that take bundle name + offset or timestamp.
------------------------------------------------------------------------------

--
-- get_row_at_commit() - by offset
--
-- Offset: 0 = HEAD, -1 = parent, -2 = grandparent, etc.
--

create or replace function get_row_at_commit(
    repository_name text,
    _offset int,
    _row_id meta.row_id,
    _record anyelement
)
returns anyelement as $$
declare
    _commit_id uuid;
begin
    if _offset > 0 then
        raise exception 'Offset must be 0 or negative (0 = HEAD, -1 = parent, etc.)';
    end if;

    select commit_id into _commit_id
    from bundle._get_commit_ancestry(bundle.head_commit_id(repository_name))
    where position = (1 - _offset);  -- position 1 = HEAD, 2 = parent, etc.

    if _commit_id is null then
        raise exception 'Commit not found at offset %', _offset;
    end if;

    return bundle._get_row_at_commit(_commit_id, _row_id, _record);
end;
$$ language plpgsql stable;


--
-- get_row_at_commit() - by timestamp
--
-- Returns row as it was at the most recent commit at or before the given time.
--

create or replace function get_row_at_commit(
    repository_name text,
    _time timestamptz,
    _row_id meta.row_id,
    _record anyelement
)
returns anyelement as $$
declare
    _commit_id uuid;
begin
    select c.id into _commit_id
    from bundle.commit c
    join bundle.repository r on c.repository_id = r.id
    where r.name = repository_name
      and c.commit_time <= _time
    order by c.commit_time desc
    limit 1;

    if _commit_id is null then
        raise exception 'No commit found at or before %', _time;
    end if;

    return bundle._get_row_at_commit(_commit_id, _row_id, _record);
end;
$$ language plpgsql stable;


--
-- get_rows_at_commit() - by offset
--

create or replace function get_rows_at_commit(
    repository_name text,
    _offset int,
    _relation_id meta.relation_id,
    _record anyelement
)
returns setof anyelement as $$
declare
    _commit_id uuid;
begin
    if _offset > 0 then
        raise exception 'Offset must be 0 or negative (0 = HEAD, -1 = parent, etc.)';
    end if;

    select commit_id into _commit_id
    from bundle._get_commit_ancestry(bundle.head_commit_id(repository_name))
    where position = (1 - _offset);

    if _commit_id is null then
        raise exception 'Commit not found at offset %', _offset;
    end if;

    return query select * from bundle._get_rows_at_commit(_commit_id, _relation_id, _record);
end;
$$ language plpgsql stable;


--
-- get_rows_at_commit() - by timestamp
--

create or replace function get_rows_at_commit(
    repository_name text,
    _time timestamptz,
    _relation_id meta.relation_id,
    _record anyelement
)
returns setof anyelement as $$
declare
    _commit_id uuid;
begin
    select c.id into _commit_id
    from bundle.commit c
    join bundle.repository r on c.repository_id = r.id
    where r.name = repository_name
      and c.commit_time <= _time
    order by c.commit_time desc
    limit 1;

    if _commit_id is null then
        raise exception 'No commit found at or before %', _time;
    end if;

    return query select * from bundle._get_rows_at_commit(_commit_id, _relation_id, _record);
end;
$$ language plpgsql stable;


--
-- get_field_at_commit() - by offset
--

create or replace function get_field_at_commit(
    repository_name text,
    _offset int,
    _field_id meta.field_id
)
returns text as $$
declare
    _commit_id uuid;
begin
    if _offset > 0 then
        raise exception 'Offset must be 0 or negative (0 = HEAD, -1 = parent, etc.)';
    end if;

    select commit_id into _commit_id
    from bundle._get_commit_ancestry(bundle.head_commit_id(repository_name))
    where position = (1 - _offset);

    if _commit_id is null then
        raise exception 'Commit not found at offset %', _offset;
    end if;

    return bundle._get_jsonb_field_at_commit(_commit_id, _field_id);
end;
$$ language plpgsql stable;


--
-- get_field_at_commit() - by timestamp
--

create or replace function get_field_at_commit(
    repository_name text,
    _time timestamptz,
    _field_id meta.field_id
)
returns text as $$
declare
    _commit_id uuid;
begin
    select c.id into _commit_id
    from bundle.commit c
    join bundle.repository r on c.repository_id = r.id
    where r.name = repository_name
      and c.commit_time <= _time
    order by c.commit_time desc
    limit 1;

    if _commit_id is null then
        raise exception 'No commit found at or before %', _time;
    end if;

    return bundle._get_jsonb_field_at_commit(_commit_id, _field_id);
end;
$$ language plpgsql stable;


------------------------------------------------------------------------------
-- ROW CHANGE ANCESTRY
--
-- Find commits where a specific row was changed.
-- Different from commit ancestry - only includes commits that modified the row.
------------------------------------------------------------------------------

--
-- _get_row_change_ancestry()
--
-- Returns commits where the given row was changed, walking back from a starting commit.
-- A row is "changed" if its field hashes differ from the parent commit
-- (including being added or deleted).
--
-- Returns change_number 1 as most recent change, with full commit metadata.
--

create or replace function _get_row_change_ancestry(
    _row_id meta.row_id,
    _starting_commit_id uuid
) returns table(
    commit_id uuid,
    change_number int,
    commit_time timestamptz,
    message text,
    author_name text,
    author_email text
) as $$
    with recursive ancestry as (
        -- Start with the starting commit
        select
            c.id as commit_id,
            c.parent_id,
            c.jsonb_fields->(_row_id::text) as row_fields,
            c.commit_time,
            c.message,
            c.author_name,
            c.author_email,
            1 as depth
        from bundle.commit c
        where c.id = _starting_commit_id

        union all

        -- Walk back through parents
        select
            c.id,
            c.parent_id,
            c.jsonb_fields->(_row_id::text),
            c.commit_time,
            c.message,
            c.author_name,
            c.author_email,
            a.depth + 1
        from bundle.commit c
        join ancestry a on c.id = a.parent_id
    ),
    changes as (
        -- Find commits where the row changed from its parent
        -- lead() gives the parent's row_fields (next depth = older commit)
        select
            a.commit_id,
            a.row_fields,
            a.commit_time,
            a.message,
            a.author_name,
            a.author_email,
            a.depth,
            lead(a.row_fields) over (order by a.depth) as parent_row_fields
        from ancestry a
    )
    select
        c.commit_id,
        row_number() over (order by c.depth)::int as change_number,
        c.commit_time,
        c.message,
        c.author_name,
        c.author_email
    from changes c
    where c.row_fields is distinct from c.parent_row_fields
    order by c.depth;
$$ language sql stable;


--
-- get_row_at_change()
--
-- Returns a row as it was at the Nth change to that row.
-- change_number 1 = most recent change, 2 = second most recent, etc.
--

create or replace function get_row_at_change(
    _repository_name text,
    _change_number int,
    _row_id meta.row_id,
    _record anyelement
) returns anyelement as $$
declare
    _commit_id uuid;
begin
    if _change_number < 1 then
        raise exception 'change_number must be >= 1 (1 = most recent change)';
    end if;

    select commit_id into _commit_id
    from bundle._get_row_change_ancestry(
        _row_id,
        bundle.head_commit_id(_repository_name)
    )
    where change_number = _change_number;

    if _commit_id is null then
        raise exception 'Change #% not found for this row', _change_number
            using hint = 'The row may not have that many changes in history';
    end if;

    return bundle._get_row_at_commit(_commit_id, _row_id, _record);
end;
$$ language plpgsql stable;


--
-- get_field_at_change()
--
-- Returns a field value as it was at the Nth change to that row.
-- change_number 1 = most recent change, 2 = second most recent, etc.
--

create or replace function get_field_at_change(
    _repository_name text,
    _change_number int,
    _field_id meta.field_id
) returns text as $$
declare
    _row_id meta.row_id;
    _commit_id uuid;
begin
    if _change_number < 1 then
        raise exception 'change_number must be >= 1 (1 = most recent change)';
    end if;

    _row_id := meta.field_id_to_row_id(_field_id);

    select commit_id into _commit_id
    from bundle._get_row_change_ancestry(
        _row_id,
        bundle.head_commit_id(_repository_name)
    )
    where change_number = _change_number;

    if _commit_id is null then
        raise exception 'Change #% not found for this row', _change_number
            using hint = 'The row may not have that many changes in history';
    end if;

    return bundle._get_jsonb_field_at_commit(_commit_id, _field_id);
end;
$$ language plpgsql stable;


------------------------------------------------------------------------------
-- VERSION RESOLVER
--
-- Parse version specifiers and return commit UUIDs.
------------------------------------------------------------------------------

--
-- resolve_version()
--
-- Parses a version specifier and returns the corresponding commit UUID.
--
-- Supported formats:
--   'latest' / 'head'  → HEAD commit
--   'head~3'           → 3 commits back from HEAD
--   '@2024-01-15'      → most recent commit at or before timestamp
--   '{uuid}'           → direct commit UUID (passthrough)
--   '1.0.0' (future)   → semver tag lookup
--

create or replace function resolve_version(
    _repository_name text,
    _version_spec text
) returns uuid as $$
declare
    _commit_id uuid;
    _offset int;
    _timestamp timestamptz;
begin
    -- Normalize to lowercase for keyword matching
    _version_spec := lower(trim(_version_spec));

    -- 'latest' or 'head' → HEAD commit
    if _version_spec in ('latest', 'head') then
        return bundle.head_commit_id(_repository_name);
    end if;

    -- 'head~N' → N commits back
    if _version_spec ~ '^head~[0-9]+$' then
        _offset := substring(_version_spec from 6)::int;

        select commit_id into _commit_id
        from bundle._get_commit_ancestry(bundle.head_commit_id(_repository_name))
        where position = (_offset + 1);  -- position 1 = HEAD, 2 = head~1, etc.

        if _commit_id is null then
            raise exception 'Commit not found at head~%', _offset
                using hint = 'The repository may not have that many commits';
        end if;

        return _commit_id;
    end if;

    -- '@timestamp' → commit at or before timestamp
    if _version_spec ~ '^@' then
        begin
            _timestamp := substring(_version_spec from 2)::timestamptz;
        exception when others then
            raise exception 'Invalid timestamp format: %', substring(_version_spec from 2)
                using hint = 'Use ISO 8601 format, e.g., @2024-01-15 or @2024-01-15T14:30:00Z';
        end;

        select c.id into _commit_id
        from bundle.commit c
        join bundle.repository r on c.repository_id = r.id
        where r.name = _repository_name
          and c.commit_time <= _timestamp
        order by c.commit_time desc
        limit 1;

        if _commit_id is null then
            raise exception 'No commit found at or before %', _timestamp;
        end if;

        return _commit_id;
    end if;

    -- Try parsing as UUID (direct commit reference)
    begin
        _commit_id := _version_spec::uuid;

        -- Verify it exists and belongs to this repository
        if not exists (
            select 1 from bundle.commit c
            join bundle.repository r on c.repository_id = r.id
            where c.id = _commit_id and r.name = _repository_name
        ) then
            raise exception 'Commit % not found in repository %', _version_spec, _repository_name;
        end if;

        return _commit_id;
    exception when invalid_text_representation then
        -- Not a UUID, continue to other formats
        null;
    end;

    -- Semver range: ^X.Y → highest version >= X.Y.0 and < (X+1).0.0
    if _version_spec ~ '^\^[0-9]+\.[0-9]+' then
        declare
            _major int;
            _minor int;
            _repo_id uuid;
        begin
            _major := (regexp_match(_version_spec, '^\^([0-9]+)'))[1]::int;
            _minor := (regexp_match(_version_spec, '^\^[0-9]+\.([0-9]+)'))[1]::int;

            select id into _repo_id from bundle.repository where name = _repository_name;

            -- Find highest version that satisfies ^X.Y (>= X.Y.0, < (X+1).0.0)
            select c.id into _commit_id
            from bundle.commit c
            where c.repository_id = _repo_id
              and c.version is not null
              and bundle.major(c.version) = _major
              and (bundle.major(c.version) > _major
                   or bundle.minor(c.version) >= _minor)
            order by c.version desc
            limit 1;

            if _commit_id is not null then
                return _commit_id;
            end if;
        end;
    end if;

    -- Exact semver: X.Y.Z → specific version
    if _version_spec ~ '^[0-9]+\.[0-9]+\.[0-9]+' then
        declare
            _repo_id uuid;
        begin
            select id into _repo_id from bundle.repository where name = _repository_name;

            select c.id into _commit_id
            from bundle.commit c
            where c.repository_id = _repo_id
              and c.version = _version_spec::bundle.version;

            if _commit_id is not null then
                return _commit_id;
            end if;
        end;
    end if;

    -- 'live' → return NULL (caller uses current database)
    if _version_spec = 'live' then
        return null;
    end if;

    raise exception 'Unknown version specifier: %', _version_spec
        using hint = 'Valid formats: live, latest, head, head~N, @timestamp, ^X.Y, X.Y.Z, or commit UUID';
end;
$$ language plpgsql stable;
