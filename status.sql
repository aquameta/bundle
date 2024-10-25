------------------------------------------------------------------------------
-- STATUS
------------------------------------------------------------------------------

create or replace function status(repository_name text default null, detailed boolean default false) returns text as $$
    declare
        _repository_ids uuid[];
        _repository_id uuid;
        c integer;
        checkout_commit_id text; head_commit_id text; author_name text; author_email text; message text; commit_time timestamptz;

        checked_out boolean;

        total_commits integer;
        head_branch_commits integer;
        head_commit_rows integer;

        tracked_rows_added integer;
        offstage_deleted_rows integer;
        offstage_changed_fields integer;

        stage_rows_to_add integer;
        stage_rows_to_remove integer;
        stage_fields_to_change integer;

        statii text := '';
    begin
        if repository_name is not null then
            -- assert repository exists
            if not delta.repository_exists(repository_name) then
                raise exception 'Repository with name % does not exist.', repository_name;
            end if;
            _repository_ids := array[(select delta.repository_id(repository_name))];
        else
            select array_agg(id order by name) from delta.repository into _repository_ids;
            -- statii := statii || E'STATUS\n======\n';
        end if;

        -- untracked rows
        select count(*) as c from delta._get_untracked_rows() into c;
        statii := statii || format(E'  - Untracked rows: %s\n', c);

        foreach _repository_id in array _repository_ids loop
            /*
             * variables
             */

            -- commit details
            select r.name, r.checkout_commit_id, r.head_commit_id, c.author_name, c.author_email, c.message, c.commit_time
            from delta.repository r
                left join delta.commit c on r.checkout_commit_id = c.id
            where r.id = _repository_id
            into repository_name, checkout_commit_id, head_commit_id, author_name, author_email, message, commit_time;

            -- checked_out
            if checkout_commit_id is not null then
                checked_out := true;
            else
                checked_out := false;
            end if;

            -- head_branch_commits
            select count(*) from delta._get_commit_ancestry (delta._head_commit_id(_repository_id)) into head_branch_commits;

            -- total_commits
            select count(*) from delta.commit where repository_id = _repository_id into total_commits;

            -- head_commit_rows
            select count(*) from delta._get_head_commit_rows(_repository_id) into head_commit_rows;

            -- unstaged changes
            select count(*) from delta._get_tracked_rows_added(_repository_id)       into tracked_rows_added;
            select count(*) from delta._get_offstage_deleted_rows(_repository_id)    into offstage_deleted_rows;
            select count(*) from delta._get_offstage_updated_fields(_repository_id)  into offstage_changed_fields;

            -- staged changes
            select count(*) from delta._get_stage_rows_to_add(_repository_id)     into stage_rows_to_add;
            select count(*) from delta._get_stage_rows_to_remove(_repository_id)   into stage_rows_to_remove;
            select count(*) from delta._get_stage_fields_to_change(_repository_id) into stage_fields_to_change;

            /*
             * status message
             */

            statii := statii || format('
[ %s ] - %s commits total, %s commits in head branch 
  - %s
  - Off-stage changes:  %s rows tracked%s
  - Staged changes:     %s rows added%s
',

                repository_name, total_commits, head_branch_commits,
                -- checked out status
                case
                    when checked_out = true then
                        format('Checked out "%s" -- %s <%s> ', message, author_name, author_email)
                    else
                        'Not checked out.'
                    end,
                -- off-stage changes status
                tracked_rows_added,
                case when checked_out = true then
                    format(', %s deletes, %s field changes ',  offstage_deleted_rows, offstage_changed_fields)
                end,

                -- staged changes status
                stage_rows_to_add,
                case when checked_out = true then
                    format(', %s deletes, %s field changes ',  stage_rows_to_remove, stage_fields_to_change)
                end
            );


        end loop;
        return statii;

    end;
$$ language plpgsql;

