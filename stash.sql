------------------------------------------------------------------------------
-- BUNDLE STASH
-- Git-stash-like functionality for saving uncommitted changes
------------------------------------------------------------------------------

-- Type for storing field values in stash
create type bundle.stash_field_value as (
    field_id meta.field_id,
    value text
);

-- Table to store stashes
create table bundle.stash (
    id uuid primary key default public.uuid_generate_v4(),
    repository_id uuid not null references bundle.repository(id) on delete cascade,
    message text,
    created_at timestamptz not null default now(),

    -- Staged state (from repository.stage_*)
    stage_rows_to_add meta.row_id[] not null default '{}',
    stage_rows_to_remove meta.row_id[] not null default '{}',
    stage_fields_to_change meta.field_id[] not null default '{}',

    -- Offstage state
    offstage_tracked_rows_added meta.row_id[] not null default '{}',
    offstage_deleted_rows meta.row_id[] not null default '{}',
    offstage_updated_fields bundle.stash_field_value[] not null default '{}'
);

create index stash_repository_id_idx on bundle.stash(repository_id);
create index stash_created_at_idx on bundle.stash(created_at);


-- Extract row_id from field_id
create or replace function bundle._field_to_row(_fid meta.field_id)
returns meta.row_id as $$
    select meta.make_row_id(
        _fid->>'schema_name',
        _fid->>'relation_name',
        array(select jsonb_array_elements_text(_fid->'pk_column_names')),
        array(select jsonb_array_elements_text(_fid->'pk_values'))
    );
$$ language sql immutable;


-- Stash all uncommitted changes (staged + offstage)
-- Saves current state, then reverts to committed state
create or replace function bundle._stash(
    _repository_id uuid,
    _message text default null
) returns uuid as $$
declare
    _stash_id uuid;
    _repo record;
    _stage_rows_add meta.row_id[] := '{}';
    _stage_rows_remove meta.row_id[] := '{}';
    _stage_fields meta.field_id[] := '{}';
    _offstage_tracked meta.row_id[] := '{}';
    _offstage_deleted meta.row_id[] := '{}';
    _offstage_fields bundle.stash_field_value[] := '{}';
    _field record;
    _row record;
    _field_value text;
    _fid meta.field_id;
    _rid meta.row_id;
begin
    -- Get repository
    select * into _repo from bundle.repository where id = _repository_id;
    if _repo is null then
        raise exception 'Repository not found: %', _repository_id;
    end if;

    -- Convert staged jsonb arrays to typed arrays
    select coalesce(array_agg(r::meta.row_id), '{}')
    into _stage_rows_add
    from jsonb_array_elements(_repo.stage_rows_to_add) r;

    select coalesce(array_agg(r::meta.row_id), '{}')
    into _stage_rows_remove
    from jsonb_array_elements(_repo.stage_rows_to_remove) r;

    select coalesce(array_agg(f::meta.field_id), '{}')
    into _stage_fields
    from jsonb_array_elements(_repo.stage_fields_to_change) f;

    -- Collect offstage updated fields with their current values
    for _field in
        select field_id from bundle._get_offstage_updated_fields(_repository_id)
    loop
        _fid := _field.field_id;

        -- Get current value from database
        execute format(
            'select %I::text from %I.%I where %I = %L',
            _fid->>'column_name',
            _fid->>'schema_name',
            _fid->>'relation_name',
            (_fid->'pk_column_names'->>0),
            (_fid->'pk_values'->>0)
        ) into _field_value;

        _offstage_fields := array_append(
            _offstage_fields,
            row(_fid, _field_value)::bundle.stash_field_value
        );
    end loop;

    -- Collect offstage tracked rows added
    for _row in
        select row_id from bundle._get_tracked_rows_added(_repository_id)
    loop
        _offstage_tracked := array_append(_offstage_tracked, _row.row_id::meta.row_id);
    end loop;

    -- Collect offstage deleted rows
    for _rid in
        select bundle._get_offstage_deleted_rows(_repository_id)
    loop
        _offstage_deleted := array_append(_offstage_deleted, _rid);
    end loop;

    -- Create stash record
    insert into bundle.stash (
        repository_id,
        message,
        stage_rows_to_add,
        stage_rows_to_remove,
        stage_fields_to_change,
        offstage_tracked_rows_added,
        offstage_deleted_rows,
        offstage_updated_fields
    ) values (
        _repository_id,
        _message,
        _stage_rows_add,
        _stage_rows_remove,
        _stage_fields,
        _offstage_tracked,
        _offstage_deleted,
        _offstage_fields
    ) returning id into _stash_id;

    -- Revert to committed state (upsert=true to handle existing rows)
    perform bundle.checkout(_repo.name, true);

    -- Clear staging area
    update bundle.repository set
        stage_rows_to_add = '[]',
        stage_rows_to_remove = '[]',
        stage_fields_to_change = '[]'
    where id = _repository_id;

    return _stash_id;
end;
$$ language plpgsql;


-- Convenience wrapper that takes repository name
create or replace function bundle.stash(
    _repository_name text,
    _message text default null
) returns uuid as $$
    select bundle._stash(
        (select id from bundle.repository where name = _repository_name),
        _message
    );
$$ language sql;


-- Stash only changes for specific rows
-- Does NOT auto-revert (selective checkout would require more work)
create or replace function bundle._stash_rows(
    _repository_id uuid,
    _row_ids meta.row_id[],
    _message text default null
) returns uuid as $$
declare
    _stash_id uuid;
    _repo record;
    _stage_rows_add meta.row_id[] := '{}';
    _stage_rows_remove meta.row_id[] := '{}';
    _stage_fields meta.field_id[] := '{}';
    _offstage_tracked meta.row_id[] := '{}';
    _offstage_deleted meta.row_id[] := '{}';
    _offstage_fields bundle.stash_field_value[] := '{}';
    _field record;
    _row record;
    _field_value text;
    _fid meta.field_id;
    _rid meta.row_id;
    _all_stage_rows_add meta.row_id[];
    _all_stage_rows_remove meta.row_id[];
    _all_stage_fields meta.field_id[];
begin
    -- Get repository
    select * into _repo from bundle.repository where id = _repository_id;
    if _repo is null then
        raise exception 'Repository not found: %', _repository_id;
    end if;

    -- Convert staged jsonb arrays to typed arrays
    select coalesce(array_agg(r::meta.row_id), '{}')
    into _all_stage_rows_add
    from jsonb_array_elements(_repo.stage_rows_to_add) r;

    select coalesce(array_agg(r::meta.row_id), '{}')
    into _all_stage_rows_remove
    from jsonb_array_elements(_repo.stage_rows_to_remove) r;

    select coalesce(array_agg(f::meta.field_id), '{}')
    into _all_stage_fields
    from jsonb_array_elements(_repo.stage_fields_to_change) f;

    -- Filter staged rows to add
    select coalesce(array_agg(r), '{}')
    into _stage_rows_add
    from unnest(_all_stage_rows_add) r
    where r = any(_row_ids);

    -- Filter staged rows to remove
    select coalesce(array_agg(r), '{}')
    into _stage_rows_remove
    from unnest(_all_stage_rows_remove) r
    where r = any(_row_ids);

    -- Filter staged fields (by row)
    select coalesce(array_agg(f), '{}')
    into _stage_fields
    from unnest(_all_stage_fields) f
    where bundle._field_to_row(f) = any(_row_ids);

    -- Collect offstage updated fields (filtered) with their current values
    for _field in
        select field_id from bundle._get_offstage_updated_fields(_repository_id)
        where bundle._field_to_row(field_id) = any(_row_ids)
    loop
        _fid := _field.field_id;

        execute format(
            'select %I::text from %I.%I where %I = %L',
            _fid->>'column_name',
            _fid->>'schema_name',
            _fid->>'relation_name',
            (_fid->'pk_column_names'->>0),
            (_fid->'pk_values'->>0)
        ) into _field_value;

        _offstage_fields := array_append(
            _offstage_fields,
            row(_fid, _field_value)::bundle.stash_field_value
        );
    end loop;

    -- Collect offstage tracked rows added (filtered)
    for _row in
        select row_id from bundle._get_tracked_rows_added(_repository_id)
        where row_id::meta.row_id = any(_row_ids)
    loop
        _offstage_tracked := array_append(_offstage_tracked, _row.row_id::meta.row_id);
    end loop;

    -- Collect offstage deleted rows (filtered)
    for _rid in
        select bundle._get_offstage_deleted_rows(_repository_id)
    loop
        if _rid = any(_row_ids) then
            _offstage_deleted := array_append(_offstage_deleted, _rid);
        end if;
    end loop;

    -- Check if there's anything to stash
    if cardinality(_stage_rows_add) = 0 and
       cardinality(_stage_rows_remove) = 0 and
       cardinality(_stage_fields) = 0 and
       cardinality(_offstage_tracked) = 0 and
       cardinality(_offstage_deleted) = 0 and
       cardinality(_offstage_fields) = 0 then
        raise exception 'No changes found for specified rows';
    end if;

    -- Create stash record
    insert into bundle.stash (
        repository_id,
        message,
        stage_rows_to_add,
        stage_rows_to_remove,
        stage_fields_to_change,
        offstage_tracked_rows_added,
        offstage_deleted_rows,
        offstage_updated_fields
    ) values (
        _repository_id,
        _message,
        _stage_rows_add,
        _stage_rows_remove,
        _stage_fields,
        _offstage_tracked,
        _offstage_deleted,
        _offstage_fields
    ) returning id into _stash_id;

    -- Remove stashed items from staging area (keep non-stashed items)
    update bundle.repository set
        stage_rows_to_add = (
            select coalesce(jsonb_agg(r), '[]')
            from jsonb_array_elements(stage_rows_to_add) r
            where not (r::meta.row_id = any(_stage_rows_add))
        ),
        stage_rows_to_remove = (
            select coalesce(jsonb_agg(r), '[]')
            from jsonb_array_elements(stage_rows_to_remove) r
            where not (r::meta.row_id = any(_stage_rows_remove))
        ),
        stage_fields_to_change = (
            select coalesce(jsonb_agg(f), '[]')
            from jsonb_array_elements(stage_fields_to_change) f
            where not (f::meta.field_id = any(_stage_fields))
        )
    where id = _repository_id;

    -- Note: Does NOT auto-revert. User must manually revert rows if desired.
    -- Selective checkout would need to restore individual rows from commit.

    return _stash_id;
end;
$$ language plpgsql;


-- Convenience wrapper for selective stash (accepts jsonb array for endpoint compatibility)
create or replace function bundle.stash_rows(
    _repository_name text,
    _row_ids jsonb,
    _message text default null
) returns uuid as $$
declare
    _row_id_array meta.row_id[];
    _elem jsonb;
begin
    -- Convert jsonb array to meta.row_id[]
    for _elem in select * from jsonb_array_elements(_row_ids)
    loop
        _row_id_array := array_append(_row_id_array, _elem::meta.row_id);
    end loop;

    return bundle._stash_rows(
        (select id from bundle.repository where name = _repository_name),
        _row_id_array,
        _message
    );
end;
$$ language plpgsql;


-- Pop the most recent stash (apply and remove)
create or replace function bundle._stash_pop(
    _repository_id uuid,
    _force boolean default false
) returns uuid as $$
declare
    _stash record;
    _sfv bundle.stash_field_value;
    _rid meta.row_id;
    _field_row_id meta.row_id;
    _conflicts text[];
    _current_value text;
begin
    -- Get most recent stash
    select * into _stash
    from bundle.stash
    where repository_id = _repository_id
    order by created_at desc
    limit 1;

    if _stash is null then
        raise exception 'No stash found for repository';
    end if;

    -- Check for conflicts: stash fields with different values from current uncommitted changes
    if not _force then
        _conflicts := '{}';
        foreach _sfv in array _stash.offstage_updated_fields
        loop
            -- Check if this field is also uncommitted
            if exists (
                select 1 from bundle._get_offstage_updated_fields(_repository_id)
                where field_id::jsonb = (((_sfv).field_id)::text::jsonb)
            ) then
                -- Get current value from database
                execute format(
                    'select %I::text from %I.%I where %I = %L',
                    (_sfv).field_id->>'column_name',
                    (_sfv).field_id->>'schema_name',
                    (_sfv).field_id->>'relation_name',
                    ((_sfv).field_id->'pk_column_names'->>0),
                    ((_sfv).field_id->'pk_values'->>0)
                ) into _current_value;

                -- Only conflict if values differ
                if _current_value is distinct from (_sfv).value then
                    _conflicts := array_append(_conflicts,
                        ((_sfv).field_id->>'schema_name') || '.' ||
                        ((_sfv).field_id->>'relation_name') || '.' ||
                        ((_sfv).field_id->>'column_name')
                    );
                end if;
            end if;
        end loop;

        if array_length(_conflicts, 1) > 0 then
            raise exception 'CONFLICT: You have uncommitted changes to: %. Applying this stash would overwrite them.', array_to_string(_conflicts, ', ');
        end if;
    end if;

    -- Restore offstage updated field values (skip if row no longer exists)
    foreach _sfv in array _stash.offstage_updated_fields
    loop
        -- Build row_id from field_id
        _field_row_id := jsonb_build_object(
            'schema_name', ((_sfv).field_id->>'schema_name'),
            'relation_name', ((_sfv).field_id->>'relation_name'),
            'pk_column_names', ((_sfv).field_id->'pk_column_names'),
            'pk_values', ((_sfv).field_id->'pk_values')
        )::meta.row_id;

        -- Only update if row still exists
        if meta.row_exists(_field_row_id) then
            execute format(
                'update %I.%I set %I = %L where %I = %L',
                ((_sfv).field_id->>'schema_name'),
                ((_sfv).field_id->>'relation_name'),
                ((_sfv).field_id->>'column_name'),
                (_sfv).value,
                (((_sfv).field_id->'pk_column_names'->>0)),
                (((_sfv).field_id->'pk_values'->>0))
            );
        end if;
    end loop;

    -- Restore offstage tracked rows (re-track them if not already tracked and row exists)
    foreach _rid in array _stash.offstage_tracked_rows_added
    loop
        -- Only track if row exists and not already tracked
        if meta.row_exists(_rid) and not bundle._is_newly_tracked(_repository_id, _rid) then
            perform bundle._track_untracked_row(_repository_id, _rid);
        end if;
    end loop;

    -- Remove stash
    delete from bundle.stash where id = _stash.id;

    return _stash.id;
end;
$$ language plpgsql;


-- Convenience wrapper
create or replace function bundle.stash_pop(
    _repository_name text,
    _force boolean default false
) returns uuid as $$
    select bundle._stash_pop(
        (select id from bundle.repository where name = _repository_name),
        _force
    );
$$ language sql;


-- Apply stash without removing (like git stash apply)
create or replace function bundle._stash_apply(
    _repository_id uuid,
    _stash_id uuid default null,
    _force boolean default false
) returns uuid as $$
declare
    _stash record;
    _sfv bundle.stash_field_value;
    _rid meta.row_id;
    _field_row_id meta.row_id;
    _conflicts text[];
    _current_value text;
begin
    -- Get specified stash or most recent
    if _stash_id is not null then
        select * into _stash
        from bundle.stash
        where id = _stash_id and repository_id = _repository_id;
    else
        select * into _stash
        from bundle.stash
        where repository_id = _repository_id
        order by created_at desc
        limit 1;
    end if;

    if _stash is null then
        raise exception 'Stash not found';
    end if;

    -- Check for conflicts: stash fields with different values from current uncommitted changes
    if not _force then
        _conflicts := '{}';
        foreach _sfv in array _stash.offstage_updated_fields
        loop
            -- Check if this field is also uncommitted
            if exists (
                select 1 from bundle._get_offstage_updated_fields(_repository_id)
                where field_id::jsonb = (((_sfv).field_id)::text::jsonb)
            ) then
                -- Get current value from database
                execute format(
                    'select %I::text from %I.%I where %I = %L',
                    (_sfv).field_id->>'column_name',
                    (_sfv).field_id->>'schema_name',
                    (_sfv).field_id->>'relation_name',
                    ((_sfv).field_id->'pk_column_names'->>0),
                    ((_sfv).field_id->'pk_values'->>0)
                ) into _current_value;

                -- Only conflict if values differ
                if _current_value is distinct from (_sfv).value then
                    _conflicts := array_append(_conflicts,
                        ((_sfv).field_id->>'schema_name') || '.' ||
                        ((_sfv).field_id->>'relation_name') || '.' ||
                        ((_sfv).field_id->>'column_name')
                    );
                end if;
            end if;
        end loop;

        if array_length(_conflicts, 1) > 0 then
            raise exception 'CONFLICT: You have uncommitted changes to: %. Applying this stash would overwrite them.', array_to_string(_conflicts, ', ');
        end if;
    end if;

    -- Restore offstage updated field values (skip if row no longer exists)
    foreach _sfv in array _stash.offstage_updated_fields
    loop
        -- Build row_id from field_id
        _field_row_id := jsonb_build_object(
            'schema_name', ((_sfv).field_id->>'schema_name'),
            'relation_name', ((_sfv).field_id->>'relation_name'),
            'pk_column_names', ((_sfv).field_id->'pk_column_names'),
            'pk_values', ((_sfv).field_id->'pk_values')
        )::meta.row_id;

        -- Only update if row still exists
        if meta.row_exists(_field_row_id) then
            execute format(
                'update %I.%I set %I = %L where %I = %L',
                ((_sfv).field_id->>'schema_name'),
                ((_sfv).field_id->>'relation_name'),
                ((_sfv).field_id->>'column_name'),
                (_sfv).value,
                (((_sfv).field_id->'pk_column_names'->>0)),
                (((_sfv).field_id->'pk_values'->>0))
            );
        end if;
    end loop;

    -- Restore offstage tracked rows (re-track them if not already tracked and row exists)
    foreach _rid in array _stash.offstage_tracked_rows_added
    loop
        -- Only track if row exists and not already tracked
        if meta.row_exists(_rid) and not bundle._is_newly_tracked(_repository_id, _rid) then
            perform bundle._track_untracked_row(_repository_id, _rid);
        end if;
    end loop;

    return _stash.id;
end;
$$ language plpgsql;


-- Drop old function signatures before creating new ones (for clean upgrades)
drop function if exists bundle.stash_apply(text, uuid);
drop function if exists bundle.stash_pop(text);
drop function if exists bundle.stash_rows(text, meta.row_id[], text);

-- Convenience wrapper
create or replace function bundle.stash_apply(
    _repository_name text,
    _stash_id uuid default null,
    _force boolean default false
) returns uuid as $$
    select bundle._stash_apply(
        (select id from bundle.repository where name = _repository_name),
        _stash_id,
        _force
    );
$$ language sql;


-- List stashes for a repository
create or replace function bundle.stash_list(
    _repository_name text
) returns table (
    id uuid,
    message text,
    created_at timestamptz,
    offstage_fields int,
    offstage_rows int,
    staged_fields int,
    staged_rows int
) as $$
    select
        s.id,
        s.message,
        s.created_at,
        cardinality(s.offstage_updated_fields),
        cardinality(s.offstage_tracked_rows_added) + cardinality(s.offstage_deleted_rows),
        cardinality(s.stage_fields_to_change),
        cardinality(s.stage_rows_to_add) + cardinality(s.stage_rows_to_remove)
    from bundle.stash s
    join bundle.repository r on r.id = s.repository_id
    where r.name = _repository_name
    order by s.created_at desc;
$$ language sql;


-- Show details of a specific stash
create or replace function bundle.stash_show(
    _stash_id uuid
) returns table (
    category text,
    item_type text,
    identifier text,
    value_preview text
) as $$
begin
    -- Offstage updated fields
    return query
    select
        'offstage'::text,
        'field'::text,
        ((sfv).field_id->>'schema_name') || '.' ||
            ((sfv).field_id->>'relation_name') || '.' ||
            ((sfv).field_id->>'column_name'),
        left((sfv).value, 80) || case when length((sfv).value) > 80 then '...' else '' end
    from bundle.stash s,
         unnest(s.offstage_updated_fields) sfv
    where s.id = _stash_id;

    -- Offstage tracked rows added
    return query
    select
        'offstage'::text,
        'row_add'::text,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from bundle.stash s,
         unnest(s.offstage_tracked_rows_added) rid
    where s.id = _stash_id;

    -- Offstage deleted rows
    return query
    select
        'offstage'::text,
        'row_delete'::text,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from bundle.stash s,
         unnest(s.offstage_deleted_rows) rid
    where s.id = _stash_id;

    -- Staged fields
    return query
    select
        'staged'::text,
        'field'::text,
        (fid->>'schema_name') || '.' || (fid->>'relation_name') || '.' || (fid->>'column_name'),
        null::text
    from bundle.stash s,
         unnest(s.stage_fields_to_change) fid
    where s.id = _stash_id;

    -- Staged rows to add
    return query
    select
        'staged'::text,
        'row_add'::text,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from bundle.stash s,
         unnest(s.stage_rows_to_add) rid
    where s.id = _stash_id;

    -- Staged rows to remove
    return query
    select
        'staged'::text,
        'row_remove'::text,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from bundle.stash s,
         unnest(s.stage_rows_to_remove) rid
    where s.id = _stash_id;
end;
$$ language plpgsql;


-- Add rows to an existing stash (captures current state of those rows)
create or replace function bundle.stash_add_rows(
    _stash_id uuid,
    _row_ids meta.row_id[]
) returns void as $$
declare
    _stash record;
    _repo record;
    _new_offstage_fields bundle.stash_field_value[] := '{}';
    _new_offstage_tracked meta.row_id[] := '{}';
    _new_offstage_deleted meta.row_id[] := '{}';
    _new_stage_rows_add meta.row_id[] := '{}';
    _new_stage_rows_remove meta.row_id[] := '{}';
    _new_stage_fields meta.field_id[] := '{}';
    _all_stage_rows_add meta.row_id[];
    _all_stage_rows_remove meta.row_id[];
    _all_stage_fields meta.field_id[];
    _field record;
    _row record;
    _fid meta.field_id;
    _rid meta.row_id;
    _field_value text;
begin
    -- Get stash
    select * into _stash from bundle.stash where id = _stash_id;
    if _stash is null then
        raise exception 'Stash not found: %', _stash_id;
    end if;

    -- Get repository
    select * into _repo from bundle.repository where id = _stash.repository_id;

    -- Convert staged jsonb arrays to typed arrays
    select coalesce(array_agg(r::meta.row_id), '{}')
    into _all_stage_rows_add
    from jsonb_array_elements(_repo.stage_rows_to_add) r;

    select coalesce(array_agg(r::meta.row_id), '{}')
    into _all_stage_rows_remove
    from jsonb_array_elements(_repo.stage_rows_to_remove) r;

    select coalesce(array_agg(f::meta.field_id), '{}')
    into _all_stage_fields
    from jsonb_array_elements(_repo.stage_fields_to_change) f;

    -- Filter staged rows to add (not already in stash)
    select coalesce(array_agg(r), '{}')
    into _new_stage_rows_add
    from unnest(_all_stage_rows_add) r
    where r = any(_row_ids)
      and not (r = any(_stash.stage_rows_to_add));

    -- Filter staged rows to remove (not already in stash)
    select coalesce(array_agg(r), '{}')
    into _new_stage_rows_remove
    from unnest(_all_stage_rows_remove) r
    where r = any(_row_ids)
      and not (r = any(_stash.stage_rows_to_remove));

    -- Filter staged fields (not already in stash)
    select coalesce(array_agg(f), '{}')
    into _new_stage_fields
    from unnest(_all_stage_fields) f
    where bundle._field_to_row(f) = any(_row_ids)
      and not (f = any(_stash.stage_fields_to_change));

    -- Collect offstage updated fields (filtered, not already in stash)
    for _field in
        select field_id from bundle._get_offstage_updated_fields(_stash.repository_id)
        where bundle._field_to_row(field_id) = any(_row_ids)
    loop
        _fid := _field.field_id;

        -- Skip if already in stash
        if exists (
            select 1 from unnest(_stash.offstage_updated_fields) f
            where (f).field_id = _fid
        ) then
            continue;
        end if;

        execute format(
            'select %I::text from %I.%I where %I = %L',
            _fid->>'column_name',
            _fid->>'schema_name',
            _fid->>'relation_name',
            (_fid->'pk_column_names'->>0),
            (_fid->'pk_values'->>0)
        ) into _field_value;

        _new_offstage_fields := array_append(
            _new_offstage_fields,
            row(_fid, _field_value)::bundle.stash_field_value
        );
    end loop;

    -- Collect offstage tracked rows added (filtered, not already in stash)
    for _row in
        select row_id from bundle._get_tracked_rows_added(_stash.repository_id)
        where row_id::meta.row_id = any(_row_ids)
          and not (row_id::meta.row_id = any(_stash.offstage_tracked_rows_added))
    loop
        _new_offstage_tracked := array_append(_new_offstage_tracked, _row.row_id::meta.row_id);
    end loop;

    -- Collect offstage deleted rows (filtered, not already in stash)
    for _rid in
        select bundle._get_offstage_deleted_rows(_stash.repository_id)
    loop
        if _rid = any(_row_ids) and not (_rid = any(_stash.offstage_deleted_rows)) then
            _new_offstage_deleted := array_append(_new_offstage_deleted, _rid);
        end if;
    end loop;

    -- Check if there's anything to add
    if cardinality(_new_stage_rows_add) = 0 and
       cardinality(_new_stage_rows_remove) = 0 and
       cardinality(_new_stage_fields) = 0 and
       cardinality(_new_offstage_tracked) = 0 and
       cardinality(_new_offstage_deleted) = 0 and
       cardinality(_new_offstage_fields) = 0 then
        raise exception 'No new changes found for specified rows';
    end if;

    -- Update stash with new items
    update bundle.stash set
        stage_rows_to_add = stage_rows_to_add || _new_stage_rows_add,
        stage_rows_to_remove = stage_rows_to_remove || _new_stage_rows_remove,
        stage_fields_to_change = stage_fields_to_change || _new_stage_fields,
        offstage_tracked_rows_added = offstage_tracked_rows_added || _new_offstage_tracked,
        offstage_deleted_rows = offstage_deleted_rows || _new_offstage_deleted,
        offstage_updated_fields = offstage_updated_fields || _new_offstage_fields
    where id = _stash_id;

    -- Remove newly stashed items from staging area
    update bundle.repository set
        stage_rows_to_add = (
            select coalesce(jsonb_agg(r), '[]')
            from jsonb_array_elements(stage_rows_to_add) r
            where not (r::meta.row_id = any(_new_stage_rows_add))
        ),
        stage_rows_to_remove = (
            select coalesce(jsonb_agg(r), '[]')
            from jsonb_array_elements(stage_rows_to_remove) r
            where not (r::meta.row_id = any(_new_stage_rows_remove))
        ),
        stage_fields_to_change = (
            select coalesce(jsonb_agg(f), '[]')
            from jsonb_array_elements(stage_fields_to_change) f
            where not (f::meta.field_id = any(_new_stage_fields))
        )
    where id = _stash.repository_id;
end;
$$ language plpgsql;


-- Remove rows from an existing stash
create or replace function bundle.stash_remove_rows(
    _stash_id uuid,
    _row_ids meta.row_id[]
) returns void as $$
declare
    _stash record;
    _removed_count int := 0;
    _new_stage_rows_add meta.row_id[];
    _new_stage_rows_remove meta.row_id[];
    _new_stage_fields meta.field_id[];
    _new_offstage_tracked meta.row_id[];
    _new_offstage_deleted meta.row_id[];
    _new_offstage_fields bundle.stash_field_value[];
begin
    -- Get stash
    select * into _stash from bundle.stash where id = _stash_id;
    if _stash is null then
        raise exception 'Stash not found: %', _stash_id;
    end if;

    -- Filter out specified rows from each array
    select coalesce(array_agg(r), '{}')
    into _new_stage_rows_add
    from unnest(_stash.stage_rows_to_add) r
    where not (r = any(_row_ids));

    select coalesce(array_agg(r), '{}')
    into _new_stage_rows_remove
    from unnest(_stash.stage_rows_to_remove) r
    where not (r = any(_row_ids));

    select coalesce(array_agg(f), '{}')
    into _new_stage_fields
    from unnest(_stash.stage_fields_to_change) f
    where not (bundle._field_to_row(f) = any(_row_ids));

    select coalesce(array_agg(r), '{}')
    into _new_offstage_tracked
    from unnest(_stash.offstage_tracked_rows_added) r
    where not (r = any(_row_ids));

    select coalesce(array_agg(r), '{}')
    into _new_offstage_deleted
    from unnest(_stash.offstage_deleted_rows) r
    where not (r = any(_row_ids));

    select coalesce(array_agg(f), '{}')
    into _new_offstage_fields
    from unnest(_stash.offstage_updated_fields) f
    where not (bundle._field_to_row((f).field_id) = any(_row_ids));

    -- Count removed items
    _removed_count := (cardinality(_stash.stage_rows_to_add) - cardinality(_new_stage_rows_add))
                    + (cardinality(_stash.stage_rows_to_remove) - cardinality(_new_stage_rows_remove))
                    + (cardinality(_stash.stage_fields_to_change) - cardinality(_new_stage_fields))
                    + (cardinality(_stash.offstage_tracked_rows_added) - cardinality(_new_offstage_tracked))
                    + (cardinality(_stash.offstage_deleted_rows) - cardinality(_new_offstage_deleted))
                    + (cardinality(_stash.offstage_updated_fields) - cardinality(_new_offstage_fields));

    if _removed_count = 0 then
        raise exception 'No matching rows found in stash';
    end if;

    -- Update stash
    update bundle.stash set
        stage_rows_to_add = _new_stage_rows_add,
        stage_rows_to_remove = _new_stage_rows_remove,
        stage_fields_to_change = _new_stage_fields,
        offstage_tracked_rows_added = _new_offstage_tracked,
        offstage_deleted_rows = _new_offstage_deleted,
        offstage_updated_fields = _new_offstage_fields
    where id = _stash_id;

    -- If stash is now empty, delete it
    if cardinality(_new_stage_rows_add) = 0 and
       cardinality(_new_stage_rows_remove) = 0 and
       cardinality(_new_stage_fields) = 0 and
       cardinality(_new_offstage_tracked) = 0 and
       cardinality(_new_offstage_deleted) = 0 and
       cardinality(_new_offstage_fields) = 0 then
        delete from bundle.stash where id = _stash_id;
        raise notice 'Stash is now empty and has been deleted';
    end if;
end;
$$ language plpgsql;


-- Drop a stash without applying
create or replace function bundle.stash_drop(
    _stash_id uuid
) returns void as $$
    delete from bundle.stash where id = _stash_id;
$$ language sql;


-- Clear all stashes for a repository
create or replace function bundle.stash_clear(
    _repository_name text
) returns int as $$
declare
    _count int;
begin
    delete from bundle.stash
    where repository_id = (select id from bundle.repository where name = _repository_name);
    get diagnostics _count = row_count;
    return _count;
end;
$$ language plpgsql;


-- Get all uncommitted changes for a repository (for stash row selector UI)
create or replace function bundle.uncommitted_changes(
    _repository_name text
) returns table (
    category text,
    item_type text,
    row_id meta.row_id,
    identifier text,
    value_preview text
) as $$
declare
    _repository_id uuid;
    _repo record;
begin
    select id into _repository_id from bundle.repository where name = _repository_name;
    select * into _repo from bundle.repository where id = _repository_id;

    -- Staged rows to add
    return query
    select
        'staged'::text,
        'row_add'::text,
        rid::meta.row_id,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from jsonb_array_elements(_repo.stage_rows_to_add) rid;

    -- Staged rows to remove
    return query
    select
        'staged'::text,
        'row_remove'::text,
        rid::meta.row_id,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from jsonb_array_elements(_repo.stage_rows_to_remove) rid;

    -- Staged fields to change
    return query
    select
        'staged'::text,
        'field'::text,
        bundle._field_to_row(fid::meta.field_id),
        (fid->>'schema_name') || '.' || (fid->>'relation_name') || '.' || (fid->>'column_name'),
        null::text
    from jsonb_array_elements(_repo.stage_fields_to_change) fid;

    -- Offstage tracked rows added
    return query
    select
        'offstage'::text,
        'row_add'::text,
        r.row_id,
        (r.row_id->>'schema_name') || '.' || (r.row_id->>'relation_name') || ':' || (r.row_id->'pk_values'->>0),
        null::text
    from bundle._get_tracked_rows_added(_repository_id) r;

    -- Offstage deleted rows
    return query
    select
        'offstage'::text,
        'row_delete'::text,
        rid,
        (rid->>'schema_name') || '.' || (rid->>'relation_name') || ':' || (rid->'pk_values'->>0),
        null::text
    from bundle._get_offstage_deleted_rows(_repository_id) rid;

    -- Offstage updated fields
    return query
    select
        'offstage'::text,
        'field'::text,
        bundle._field_to_row(f.field_id),
        (f.field_id->>'schema_name') || '.' || (f.field_id->>'relation_name') || '.' || (f.field_id->>'column_name'),
        null::text
    from bundle._get_offstage_updated_fields(_repository_id) f;
end;
$$ language plpgsql;


-- Export a stash to portable JSON format
create or replace function bundle.stash_to_json(
    _stash_id uuid
) returns jsonb as $$
declare
    _stash record;
    _repo_name text;
    _offstage_fields_json jsonb;
begin
    -- Get stash and repository name
    select s.*, r.name as repository_name
    into _stash
    from bundle.stash s
    join bundle.repository r on r.id = s.repository_id
    where s.id = _stash_id;

    if _stash is null then
        raise exception 'Stash not found: %', _stash_id;
    end if;

    -- Convert stash_field_value array to jsonb array
    select coalesce(jsonb_agg(jsonb_build_object(
        'field_id', sfv.field_id,
        'value', sfv.value
    )), '[]'::jsonb)
    into _offstage_fields_json
    from unnest(_stash.offstage_updated_fields) sfv;

    return jsonb_build_object(
        'version', 1,
        'type', 'bundle.stash',
        'repository_name', _stash.repository_name,
        'message', _stash.message,
        'created_at', _stash.created_at,
        'stage_rows_to_add', to_jsonb(_stash.stage_rows_to_add),
        'stage_rows_to_remove', to_jsonb(_stash.stage_rows_to_remove),
        'stage_fields_to_change', to_jsonb(_stash.stage_fields_to_change),
        'offstage_tracked_rows_added', to_jsonb(_stash.offstage_tracked_rows_added),
        'offstage_deleted_rows', to_jsonb(_stash.offstage_deleted_rows),
        'offstage_updated_fields', _offstage_fields_json
    );
end;
$$ language plpgsql;


-- Import a stash from JSON format
create or replace function bundle.stash_from_json(
    _json jsonb
) returns uuid as $$
declare
    _repository_id uuid;
    _stash_id uuid;
    _offstage_fields bundle.stash_field_value[];
    _elem jsonb;
begin
    -- Validate version
    if (_json->>'version')::int != 1 then
        raise exception 'Unsupported stash version: %', _json->>'version';
    end if;

    -- Find repository by name
    select id into _repository_id
    from bundle.repository
    where name = _json->>'repository_name';

    if _repository_id is null then
        raise exception 'Repository not found: %', _json->>'repository_name';
    end if;

    -- Convert offstage_updated_fields from jsonb to typed array
    _offstage_fields := '{}';
    for _elem in select * from jsonb_array_elements(_json->'offstage_updated_fields')
    loop
        _offstage_fields := array_append(
            _offstage_fields,
            row((_elem->>'field_id')::meta.field_id, _elem->>'value')::bundle.stash_field_value
        );
    end loop;

    -- Insert new stash
    insert into bundle.stash (
        repository_id,
        message,
        created_at,
        stage_rows_to_add,
        stage_rows_to_remove,
        stage_fields_to_change,
        offstage_tracked_rows_added,
        offstage_deleted_rows,
        offstage_updated_fields
    ) values (
        _repository_id,
        _json->>'message',
        coalesce((_json->>'created_at')::timestamptz, now()),
        (select coalesce(array_agg(r::meta.row_id), '{}') from jsonb_array_elements(_json->'stage_rows_to_add') r),
        (select coalesce(array_agg(r::meta.row_id), '{}') from jsonb_array_elements(_json->'stage_rows_to_remove') r),
        (select coalesce(array_agg(f::meta.field_id), '{}') from jsonb_array_elements(_json->'stage_fields_to_change') f),
        (select coalesce(array_agg(r::meta.row_id), '{}') from jsonb_array_elements(_json->'offstage_tracked_rows_added') r),
        (select coalesce(array_agg(r::meta.row_id), '{}') from jsonb_array_elements(_json->'offstage_deleted_rows') r),
        _offstage_fields
    ) returning id into _stash_id;

    return _stash_id;
end;
$$ language plpgsql;
