------------------------------------------------------------------------------
-- STATUS
------------------------------------------------------------------------------

create or replace function status(repository_name text default null, detailed boolean default false) returns void as $$
    declare
        _repository_ids uuid[];
        _repository_id uuid;
        rec record;
        c integer;
        checkout_commit_id text; head_commit_id text; author_name text; author_email text; message text; commit_time timestamptz;

        tracked_rows_added integer;
        offstage_rows_deleted integer;
        offstage_fields_changed integer;

        stage_rows_added integer;
        stage_rows_deleted integer;
        stage_fields_changed integer;

    begin
        if repository_name is not null then
            -- assert repository exists
            if not delta.repository_exists(repository_name) then
                raise exception 'Repository with name % does not exist.', repository_name;
            end if;
            _repository_ids := array[(select delta.repository_id(repository_name))];
        else
            select array_agg(id) from delta.repository into _repository_ids;
            raise notice 'STATUS';
            raise notice '======';
        end if;

        -- untracked rows
        select count(*) as c from untracked_rows() into c;
        raise notice '  - Untracked rows: %', c;

        foreach _repository_id in array _repository_ids loop

            select r.name, r.checkout_commit_id, r.head_commit_id, c.author_name, c.author_email, c.message, c.commit_time
            from delta.repository r
                left join delta.commit c on r.checkout_commit_id = c.id
            into repository_name, checkout_commit_id, head_commit_id, author_name, author_email, message, commit_time;

            -- heading
            raise notice '';
            raise notice '[ % ]', delta._repository_name(_repository_id);
            if checkout_commit_id is not null then
                raise notice 'Checked out "%" -- % <%>', message, author_name, author_email;
            else
                raise notice 'Not checked out.';
            end if;
            raise notice '----------------------------------------------------------------------------------';

            -- unstaged changes
            select count(*) from _tracked_rows_added(_repository_id)       into tracked_rows_added;
            select count(*) from _offstage_rows_deleted(_repository_id)    into offstage_rows_deleted;
            select count(*) from _offstage_fields_changed(_repository_id)  into offstage_fields_changed;
            raise notice '  - Unstaged changes:  % tracked rows, % rows deleted, % fields changed', tracked_rows_added, offstage_rows_deleted, offstage_fields_changed;

            -- staged changes
            select count(*) from _stage_rows_added(_repository_id)     into stage_rows_added;
            select count(*) from _stage_rows_deleted(_repository_id)   into stage_rows_deleted;
            select count(*) from _stage_fields_changed(_repository_id) into stage_fields_changed;
            raise notice '  - Staged changes:  % rows added, % rows deleted, % fields changed', stage_rows_added, stage_rows_deleted, stage_fields_changed;
        end loop;

    end;
$$ language plpgsql;
