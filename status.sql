------------------------------------------------------------------------------
-- STATUS
------------------------------------------------------------------------------

/*
this would be nice:


                    io.bundle.core.repository
             +----------------------------------------+
             | 12 commits                             |
             +----------------------------------------+
 head commit | "Ignore rules." - 2024-12-25 4:20pm    |
    contents | (4) bundle.ignored_table               |
             | (3) bundle.ignored_schema              |
             +----------------------------------------+
          db | 0 tracked  | 0 deleted   | 0 updated   |
             +----------------------------------------+
       stage | 0 to added | 0 to remove | 0 to change |
             +----------------------------------------+


*/

--
-- _status()
--
-- Returns structured status data for one or all repositories
--

create or replace function _status(_repository_id uuid default null)
returns table (
    -- repository info
    repository_id uuid,
    repository_name text,

    -- commit info
    checkout_commit_id uuid,
    head_commit_id uuid,
    author_name text,
    author_email text,
    message text,
    commit_time timestamptz,

    -- state
    checked_out boolean,
    total_commits integer,
    head_branch_commits integer,
    head_commit_rows integer,

    -- offstage changes
    tracked_rows_added integer,
    offstage_deleted_rows integer,
    offstage_updated_fields integer,

    -- staged changes
    stage_rows_to_add integer,
    stage_rows_to_remove integer,
    stage_fields_to_change integer,

    -- row counts by relation (array of {relation_id, row_count})
    row_count_by_relation jsonb
)
as $$
    select
        r.id as repository_id,
        r.name as repository_name,

        -- commit info
        r.checkout_commit_id,
        r.head_commit_id,
        c.author_name,
        c.author_email,
        c.message,
        c.commit_time,

        -- state
        r.checkout_commit_id is not null as checked_out,
        (select count(*) from bundle.commit where repository_id = r.id) as total_commits,
        (select count(*) from bundle._get_commit_ancestry(r.head_commit_id)) as head_branch_commits,
        (select count(*) from bundle._get_head_commit_rows(r.id)) as head_commit_rows,

        -- offstage changes
        (select count(*) from bundle._get_tracked_rows_added(r.id)) as tracked_rows_added,
        (select count(*) from bundle._get_offstage_deleted_rows(r.id)) as offstage_deleted_rows,
        (select count(*) from bundle._get_offstage_updated_fields(r.id)) as offstage_updated_fields,

        -- staged changes
        (select count(*) from bundle._get_stage_rows_to_add(r.id)) as stage_rows_to_add,
        (select count(*) from bundle._get_stage_rows_to_remove(r.id)) as stage_rows_to_remove,
        (select count(*) from bundle._get_stage_fields_to_change(r.id)) as stage_fields_to_change,

        -- row counts by relation
        (select jsonb_agg(jsonb_build_object('relation_id', relation_id, 'row_count', row_count))
         from bundle._get_commit_row_count_by_relation(r.head_commit_id)
        ) as row_count_by_relation

    from bundle.repository r
        left join bundle.commit c on r.checkout_commit_id = c.id
    where _repository_id is null or r.id = _repository_id
    order by r.name;
$$ language sql;


--
-- status()
--
-- Returns formatted text status by calling _status() for data
--

create or replace function status(_repository_name text default null, detailed boolean default false) returns text as $$
    declare
        _repository_id uuid;
        s record;
        untracked_row_count integer;
        row_count_summary text;
        statii text := '';

        _tracked_rows_added text;
        _offstage_deleted_rows text;
        _offstage_updated_fields text;
        _stage_rows_to_add text;
        _stage_rows_to_remove text;
        _stage_fields_to_change text;
    begin
        -- get repository_id if name provided
        if _repository_name is not null then
            if not bundle.repository_exists(_repository_name) then
                raise exception 'Repository with name % does not exist.', _repository_name;
            end if;
            _repository_id := bundle.repository_id(_repository_name);
        end if;

        -- untracked rows (global count)
        select count(*) from bundle._get_untracked_rows() into untracked_row_count;
        statii := statii || format(E'+ Untracked rows: %s\n', untracked_row_count);
        statii := statii || format(E'+------------------------------------------------------------------------------\n');

        -- iterate over status data from _status()
        for s in select * from bundle._status(_repository_id) loop

            -- format row count summary from jsonb
            select string_agg(
                '(' || (elem->>'row_count') || ') '
                    || (elem->'relation_id'->>'schema_name') || '.'
                    || (elem->'relation_id'->>'name'),
                E'\n+             | '
            )
            from jsonb_array_elements(s.row_count_by_relation) elem
            into row_count_summary;

            -- main status display
            statii := statii || format(
'+ %s
+             +----------------------------------------------------------------
+             | %s commits, %s in this branch
+             +----------------------------------------------------------------
+    contents | %s
+    checkout | %s
+             +----------------------------------------------------------------
+          db | %s tracked %s
+             +----------------------------------------------------------------
+       stage | %s to add  %s
+             +----------------------------------------------------------------
+
',
                -- heading
                s.repository_name, s.total_commits, s.head_branch_commits,

                -- contents summary
                row_count_summary,

                -- checked out status
                case
                    when s.checked_out then
                        format('"%s" -- %s <%s> ', s.message, s.author_name, s.author_email)
                    else
                        'Not checked out.'
                end,

                -- off-stage changes status
                s.tracked_rows_added,
                case when s.checked_out then
                    format('| %s deleted   | %s updated',  s.offstage_deleted_rows, s.offstage_updated_fields)
                end,

                -- staged changes status
                s.stage_rows_to_add,
                case when s.checked_out then
                    format('| %s to remove | %s to change',  s.stage_rows_to_remove, s.stage_fields_to_change)
                end
            );

            -------------- detailed section ---------------------
            if detailed then
                select r.tracked_rows_added from bundle.repository r where r.id = s.repository_id into _tracked_rows_added;
                select string_agg(r::text, ',') from bundle._get_offstage_deleted_rows(s.repository_id) r into _offstage_deleted_rows;
                select string_agg(r::text, ',') from bundle._get_offstage_updated_fields(s.repository_id) r into _offstage_updated_fields;
                select r.stage_rows_to_add from bundle.repository r where r.id = s.repository_id into _stage_rows_to_add;
                select r.stage_rows_to_remove from bundle.repository r where r.id = s.repository_id into _stage_rows_to_remove;
                select r.stage_fields_to_change from bundle.repository r where r.id = s.repository_id into _stage_fields_to_change;

                statii := statii || E'\n OFFSTAGE:';
                statii := statii || E'\n track:' || coalesce(_tracked_rows_added, 'NULL');
                statii := statii || E'\n delete:' || coalesce(_offstage_deleted_rows, 'NULL');
                statii := statii || E'\n update:' || coalesce(_offstage_updated_fields, 'NULL');

                statii := statii || E'\n STAGE:';
                statii := statii || E'\n adds :' || coalesce(_stage_rows_to_add,'NULL');
                statii := statii || E'\n removes :' || coalesce(_stage_rows_to_remove, 'NULL');
                statii := statii || E'\n changes: ' || coalesce(_stage_fields_to_change, 'NULL');
            end if;

        end loop;

        statii := statii || format(E'+------------------------------------------------------------------------------\n');
        return statii;

    end;
$$ language plpgsql;


--
-- _get_commit_row_status()
--
-- Returns a summary of a commit's rows compared to the database state
-- Groups rows by row_id and shows whether they exist in db
--


create type row_state as enum ('tracked', 'staged', 'in_commit');

create or replace function _get_commit_status(_commit_id uuid)
returns table (
    -- row-level
    row_id meta.row_id,
    row_state row_state,
    row_exists boolean,
    row_staged_to_remove boolean,

    -- field-level
    has_field_changes boolean,
    offstage_fields_updated jsonb,
    stage_fields_to_changes jsonb,

    -- schema-level
    has_schema_changes boolean,
    new_columns text[],
    deleted_columns text[]
)
as $$
    with repo as (
        select r.id
        from bundle.commit c
            join bundle.repository r on c.repository_id=r.id
        where c.id = _commit_id
    )


    -- commit


    select
        -- row-level
        dcr.row_id,
        'in_commit'::bundle.row_state as row_state,
        dcr.exists as row_exists,
        srtr.row_id is not null as row_staged_to_remove,

        -- field-level
        jsonb_agg(cf.value_hash) != jsonb_agg(dcf.value_hash) as has_field_changes,

        null, -- jsonb_object_agg(cf.field_id->>'column_name', cf.value_hash) as commit_value_hashes,
        null, -- jsonb_object_agg(dcf.field_id->>'column_name', dcf.value_hash) as db_value_hashes,
        false,
        null::text[], -- TODO: compare db_value_hashes with commit_value_hashes for schema changes
        null::text[]

    from repo r,
        bundle._get_db_commit_rows(_commit_id) dcr
        left join bundle._get_stage_rows_to_remove(r.id) srtr
            on dcr.row_id = srtr.row_id
        join bundle._get_commit_fields(_commit_id) cf
            on dcr.row_id = meta.field_id_to_row_id(cf.field_id)
        left join bundle._get_db_commit_fields(_commit_id) dcf
            on cf.field_id = dcf.field_id
    group by dcr.row_id, srtr.row_id, dcr.exists


    union


    -- stage
    select
        srta.row_id,
        'staged' as row_state,
        srta.row_exists,
        false as row_staged_to_remove,

        null as has_field_changes,
        null::jsonb as offstage_fields_updated,
        null::jsonb as stage_fields_to_change,

        false as has_schema_changes,
        null as new_columns,
        null as deleted_columns

        from bundle.repository r,
        bundle._get_db_stage_rows_added(r.id) srta


    union


    -- tracked
    select
        tra.row_id,
        'tracked' as row_state,
        tra.row_exists,
        false as row_staged_to_remove,

        null as has_field_changes,
        null::jsonb as offstage_fields_updated,
        null::jsonb as stage_fields_to_change,

        false as has_schema_changes,
        null as new_columns,
        null as deleted_columns

        from bundle.repository r,
        bundle._get_db_tracked_rows_added(r.id) tra

$$ language sql;
