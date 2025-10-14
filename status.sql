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
    contents | (4) bundle.ignored_table                |
             | (3) bundle.ignored_schema               |
             +----------------------------------------+
          db | 0 tracked  | 0 deleted   | 0 updated   |
             +----------------------------------------+
       stage | 0 to added | 0 to remove | 0 to change |
             +----------------------------------------+


*/

create or replace function _status(_repository_id uuid default null, detailed boolean default false) returns text as $$
    declare
        repository_name text;
        _repository_ids uuid[];
        untracked_row_count integer;
        checkout_commit_id text; head_commit_id text; author_name text; author_email text; message text; commit_time timestamptz;

        checked_out boolean;

        total_commits integer;
        head_branch_commits integer;
        head_commit_rows integer;

        tracked_rows_added integer;
        offstage_deleted_rows integer;
        offstage_updated_fields integer;

        _tracked_rows_added text;
        _offstage_deleted_rows text;
        _offstage_updated_fields text;

        stage_rows_to_add integer;
        stage_rows_to_remove integer;
        stage_fields_to_change integer;

        _stage_rows_to_add text;
        _stage_rows_to_remove text;
        _stage_fields_to_change text;

        row_count_summary text;

        statii text := '';
    begin
        repository_name := bundle._repository_name(_repository_id);

        if repository_name is not null then
            -- assert repository exists
            if not bundle.repository_exists(repository_name) then
                raise exception 'Repository with name % does not exist.', repository_name;
            end if;
            _repository_ids := array[(select bundle.repository_id(repository_name))];
        else
            select coalesce(array_agg(id order by name), '{}') from bundle.repository into _repository_ids;
            -- statii := statii || E'STATUS\n======\n';
        end if;

        -- untracked rows
        select count(*) as c from bundle._get_untracked_rows() into untracked_row_count;
        statii := statii || format(E'+ Untracked rows: %s\n', untracked_row_count);
        statii := statii || format(E'+------------------------------------------------------------------------------\n');

        foreach _repository_id in array _repository_ids loop
            /*
             * variables
             */

            -- commit details
            select r.name, r.checkout_commit_id, r.head_commit_id, c.author_name, c.author_email, c.message, c.commit_time
            from bundle.repository r
                left join bundle.commit c on r.checkout_commit_id = c.id
            where r.id = _repository_id
            into repository_name, checkout_commit_id, head_commit_id, author_name, author_email, message, commit_time;

            -- checked_out
            if checkout_commit_id is not null then
                checked_out := true;
            else
                checked_out := false;
            end if;

            -- head_branch_commits
            select count(*) from bundle._get_commit_ancestry (bundle._head_commit_id(_repository_id)) into head_branch_commits;

            -- total_commits
            select count(*) from bundle.commit where repository_id = _repository_id into total_commits;

            -- head_commit_rows
            select count(*) from bundle._get_head_commit_rows(_repository_id) into head_commit_rows;

            -- offstage changes
            select count(*) from bundle._get_tracked_rows_added(_repository_id)       into tracked_rows_added;
            select count(*) from bundle._get_offstage_deleted_rows(_repository_id)    into offstage_deleted_rows;
            select count(*) from bundle._get_offstage_updated_fields(_repository_id)  into offstage_updated_fields;

            -- staged changes
            select count(*) from bundle._get_stage_rows_to_add(_repository_id)     into stage_rows_to_add;
            select count(*) from bundle._get_stage_rows_to_remove(_repository_id)   into stage_rows_to_remove;
            select count(*) from bundle._get_stage_fields_to_change(_repository_id) into stage_fields_to_change;

            select string_agg(
                '(' || row_count || ') '
                    || (relation_id->>'schema_name') || '.'
                    || (relation_id->>'name'),
                E'\n+             | ' -- delim
            )
            from bundle._get_commit_row_count_by_relation(bundle._head_commit_id(_repository_id))
            into row_count_summary;

            -- more ideas:
            -- topology status
            -- check for dirty stage status



            /*
             * status message
             */

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
                repository_name, total_commits, head_branch_commits,

                -- contents summary
                row_count_summary,

                -- checked out status
                case
                    when checked_out = true then
                        format('"%s" -- %s <%s> ', message, author_name, author_email)
                    else
                        'Not checked out.'
                end,

                -- off-stage changes status
                tracked_rows_added,
                case when checked_out = true then
                    format('| %s deleted   | %s updated',  offstage_deleted_rows, offstage_updated_fields)
                end,

                -- staged changes status
                stage_rows_to_add,
                case when checked_out = true then
                    format('| %s to remove | %s to change',  stage_rows_to_remove, stage_fields_to_change)
                end
            );


            -------------- detailed section ---------------------
            if detailed is true then
                _tracked_rows_added      := (select r.tracked_rows_added from bundle.repository r where r.id = _repository_id);
                _offstage_deleted_rows   := (select string_agg(r::text, ',') from bundle._get_offstage_deleted_rows(_repository_id) r);
                _offstage_updated_fields := (select string_agg(r::text, ',') from bundle._get_offstage_updated_fields(_repository_id) r);

                _stage_rows_to_add       := (select r.stage_rows_to_add from bundle.repository r where r.id = _repository_id);
                _stage_fields_to_change  := (select r.stage_fields_to_change from bundle.repository r where r.id = _repository_id);
                _stage_rows_to_remove    := (select r.stage_rows_to_remove from bundle.repository r where r.id = _repository_id);

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


create or replace function status(repository_name text default null, detailed boolean default false) returns text as $$
    select bundle._status(bundle.repository_id(repository_name), detailed);
$$ language sql;


--
-- _get_commit_status()
--
-- Returns a summary of a commit's rows compared to the database state
-- Groups rows by row_id and shows whether they exist in both commit and db
--


create type row_state as enum ('tracked', 'staged', 'in_commit');

drop function _get_commit_status;
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
    select
        -- row-level
        dcr.row_id,
        'in_commit'::bundle.row_state as row_state,
        dcr.exists as row_exists,
        srtr.row_id is not null as row_staged_to_remove,

        -- field-level
        jsonb_agg(cf.value_hash) != jsonb_agg(dcf.value_hash) as has_field_changes,

        jsonb_object_agg(cf.field_id->>'column_name', cf.value_hash) as commit_value_hashes,
        jsonb_object_agg(dcf.field_id->>'column_name', dcf.value_hash) as db_value_hashes,
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


    select 
        srta.row_id,
        'staged' as row_state,
        true as row_exists, -- TODO: invent _get_db_stage_rows_row_add()
        false as row_staged_to_remove,

        null as has_field_changes,
        null as offstage_fields_updated,
        null as stage_fields_to_change,

        false as has_schema_changes,
        null as new_columns,
        null as deleted_columns

        from bundle.repository r,
        bundle._get_stage_rows_to_add(r.id) srta


    union


    select 
        srta.row_id,
        'tracked' as row_state,
        true as row_exists, -- TODO: invent _get_db_stage_rows_row_add()
        false as row_staged_to_remove,

        null as has_field_changes,
        null as offstage_fields_updated,
        null as stage_fields_to_change,

        false as has_schema_changes,
        null as new_columns,
        null as deleted_columns

        from bundle.repository r,
        bundle._get_tracked_rows_added(r.id) srta

$$ language sql;
