------------------------------------------------------------------------------
-- TRACKED / UNTRACKED ROWS
------------------------------------------------------------------------------

/*
 * _is_newly_tracked()
 */

create or replace function _is_newly_tracked( repository_id uuid, row_id meta.row_id ) returns boolean as $$
declare
    row_count integer;
begin
    select count(*) into row_count from bundle.repository
    where id = repository_id
        and tracked_rows_added @> jsonb_build_array(row_id);

    if row_count > 0 then
        return true;
    else
        return false;
    end if;
end;
$$ language plpgsql;


/*
 * track_untracked_row()
 *
 * Adds an untracked row to a repository's tracked_rows_added column.
 */

create or replace function _track_untracked_row( _repository_id uuid, row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not bundle._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        /*
        TODO: cruft from pre-json days, refactor this to check repository.tracked_rows_added
        if meta.row_exists(meta.make_row_id('bundle','tracked_row_added', 'row_id', row_id::text)) then
            raise exception 'Row with row_id % is already tracked.', row_id;
        end if;
        */

        -- assert row exists
        if not meta.row_exists(row_id) then
            raise exception 'Row with row_id % does not exist.', row_id;
        end if;

        -- assert row is not already tracked
        if bundle._is_newly_tracked(_repository_id, row_id) then
            raise exception 'Row with row_id % is already tracked.', row_id;
        end if;

        update bundle.repository set tracked_rows_added = tracked_rows_added || row_id where id = _repository_id;
    end;
$$ language plpgsql;


create or replace function track_untracked_row( repository_name text, row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not bundle.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform bundle._track_untracked_row(
            bundle.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- untrack_tracked_row()
--

create or replace function _untrack_tracked_row( _repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        c integer;
    begin

        select count(*) into c from bundle.repository where id = _repository_id and tracked_rows_added @> jsonb_build_array(_row_id);
        if c < 1 then
            raise exception 'Row with row_id % cannot be removed because it is not tracked by supplied repository.', _row_id::text;
        end if;

        update bundle.repository set tracked_rows_added = (
            select coalesce(jsonb_agg(elem), '[]'::jsonb)
            from jsonb_array_elements(tracked_rows_added) elem
            where elem != _row_id::jsonb
        ) where id = _repository_id;

        return tracked_row_id;
    end;
$$ language plpgsql;

create or replace function untrack_tracked_row( name text, row_id meta.row_id ) returns uuid as $$
    select bundle._untrack_tracked_row(bundle.repository_id(name), row_id);
$$ language sql;


--
-- untrack_tracked_rows_added()
--

create or replace function _untrack_tracked_rows_added( _repository_id uuid ) returns void as $$
    update bundle.repository set tracked_rows_added='[]'::jsonb where id = _repository_id;
$$ language sql;


--
-- tracked_rows_added
--

create or replace function _get_tracked_rows_added( _repository_id uuid )
returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements(tracked_rows_added)::meta.row_id
    from bundle.repository
    where id = _repository_id;
$$ language sql;

create or replace function get_tracked_rows_added( repository_name text )
returns table(repository_id uuid, row_id meta.row_id) as $$
    select bundle._get_Tracked_rows_added(
        bundle.repository_id(repository_name)
    );
$$ language sql;

create or replace view tracked_row_added as
    select id as repository_id, jsonb_array_elements(tracked_rows_added)::meta.row_id as row_id
    from bundle.repository;
