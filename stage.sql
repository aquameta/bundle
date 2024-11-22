------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS

-- Organized as
--   a) functions that change data
--   b) functions that just get info
------------------------------------------------------------------------------


-------------------------------------------------
-- Staging / Unstaging Action Functions
-------------------------------------------------

--
-- stage_tracked_row()
--

create or replace function _stage_tracked_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    begin
        -- assert repository exists
        if not ditty._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- check that it's not already staged
        if meta.row_exists(meta.row_id('ditty','stage_row_to_add', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;

        -- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform ditty._untrack_tracked_row(_repository_id, _row_id);

        -- stage
        -- TODO: are we supposed to be using to_jsonb here or jsonb_build_object?
        update ditty.repository
        -- set stage_rows_to_add = stage_rows_to_add || jsonb_build_object(_row_id::text, ditty._get_db_row_field_hashes_obj(_row_id))
        set stage_rows_to_add = stage_rows_to_add || to_jsonb(_row_id::text)
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_tracked_row( repository_name text, row_id meta.row_id )
returns void as $$
    begin
        -- assert repository exists
        if not ditty.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform ditty._stage_tracked_row(
            ditty.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- unstage_tracked_row() TODO
--




--
-- stage_row_to_remove()
--

create or replace function _stage_row_to_remove( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not ditty._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- TODO: make sure the row is in the head commit

        -- stage
        update ditty.repository
        set stage_rows_to_remove = stage_rows_to_remove || to_jsonb(_row_id::text)
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_to_remove( repository_name text, row_id meta.row_id )
returns void as $$
    begin

        -- assert repository exists
        if not ditty.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform ditty._stage_row_to_remove(
            ditty.repository_id(repository_name),
            row_id
        );
    end;
$$ language plpgsql;


--
-- unstage_row_to_remove()
--
-- Removes a staged row (add or delete) from the stage.  Split these up?

create or replace function _unstage_row_to_remove( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from ditty.stage_row_to_add sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        -- TODO: fix.
        update ditty.repository
        set stage_rows_to_remove = stage_rows_to_remove - array[_row_id::text]
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function unstage_row_to_remove( _repository_id uuid, row_id meta.row_id )
returns void as $$
    select ditty._unstage_row_to_remove(_repository_id, row_id);
$$ language sql;


--
-- stage a field change
--

create or replace function _stage_field_to_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
    begin
        -- TODO: assert field is changed and part of repo
        update ditty.repository
        -- obj approach: set stage_fields_to_change = stage_fields_to_change || jsonb_build_object(_field_id::text, meta.field_id_literal_value(_field_id))
        set stage_fields_to_change = stage_fields_to_change || to_jsonb(_field_id::text)
        where id = _repository_id;
        return true;
    end;
$$ language plpgsql;

--
-- unstage a field change
--

/*
TODO
create or replace function _unstage_field_to_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
*/

--
-- empty_stage()
--

create or replace function _empty_stage( _repository_id uuid ) returns void as $$
    begin
        update ditty.repository set stage_rows_to_add = '[]' where id = _repository_id;
        update ditty.repository set stage_rows_to_remove = '[]' where id = _repository_id;
        update ditty.repository set stage_fields_to_change = '[]' where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function empty_stage( repository_name text ) returns void as $$
    select ditty._empty_stage(ditty.repository_id(repository_name));
$$ language sql;



-------------------------------------------------
-- Set Views / Functions
-- Convention: _get_*()
-------------------------------------------------

--
-- get_stage_rows_to_add()
--

create or replace function _get_stage_rows_to_add( _repository_id uuid ) returns table (repository_id uuid,row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(stage_rows_to_add)::meta.row_id
    from ditty.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_add as
select id as repository_id, jsonb_array_elements_text(stage_rows_to_add)::meta.row_id as row_id
from ditty.repository;


--
-- get_stage_rows_to_remove()
--

create or replace function _get_stage_rows_to_remove( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id
    from ditty.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_remove as
select id as repository_id, jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id as row_id
from ditty.repository;


--
-- get_stage_fields_to_change()
--

create or replace function _get_stage_fields_to_change( _repository_id uuid ) returns setof meta.field_id as $$
    select jsonb_array_elements_text(stage_fields_to_change)::meta.field_id
    from ditty.repository
    where id = _repository_id;
$$ language sql;

create view stage_field_to_change as
    -- select id, jsonb_array_elements_text(stage_fields_to_change)::meta.field_id
select id as repository_id, jsonb_array_elements_text(stage_fields_to_change)::meta.field_id as field_id
from ditty.repository;


--
-- _is_staged()
--

create or replace function _is_staged( repository_id uuid, row_id meta.row_id ) returns boolean as $$
begin
    return (
        select jsonb_array_elements_text(stage_rows_to_add) = row_id::text
        from ditty.repository
        where id = repository_id
    );
end;
$$ language plpgsql;



--
-- get_tracked_rows()
-- Returns *all* tracked rows: Newly tracked, staged and head_commit rows

create or replace function _get_tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from ditty._get_head_commit_rows(_repository_id)

    -- ...plus newly tracked rows
    union

    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id
    from ditty.repository r
    where r.id = _repository_id

    -- plus staged rows
    union

    select jsonb_array_elements_text(r.stage_rows_to_add)::meta.row_id
    from ditty.repository r
    where r.id = _repository_id
$$ language sql;

create or replace function get_tracked_rows( repository_name text ) returns setof meta.row_id as $$
    select ditty._get_tracked_rows(
        ditty.repository_id(repository_name)
    );
$$ language sql;



--
-- stage_deleted_rows() TODO
--



create or replace function _get_offstage_deleted_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- rows deleted from head commit
    select row_id
    from ditty._get_db_head_commit_rows(_repository_id)
        where exists = false

    except

    -- minus those that have been staged for deletion
    select jsonb_array_elements_text(r.stage_rows_to_remove)::meta.row_id
    from ditty.repository r where r.id = _repository_id;
$$ language sql;


--
-- get_stage_updated_fields() TODO
--

--
-- get_offstage_updated_fields()
--

create or replace function _get_offstage_updated_fields( _repository_id uuid ) returns setof ditty.field_hash as $$
    -- fields whos commit hash is different from db hash
    select hcf.field_id, dbf.value_hash
    -- fields from head commit
    from ditty._get_head_commit_fields(_repository_id) hcf
        -- left joined because db_fields() excludes dropped columns and columns may have been dropped
        left join ditty._get_db_head_commit_fields(_repository_id) dbf on dbf.field_id = hcf.field_id
    -- where value is different
    where hcf.value_hash != dbf.value_hash

    except

    select field_id, value_hash from ditty._get_db_stage_fields_to_change(_repository_id);
$$ language sql;


--
-- _get_stage_rows()
--

create type stage_row as (row_id meta.row_id, new_row boolean);
create or replace function _get_stage_rows( _repository_id uuid ) returns setof stage_row as $$
    select row_id, false as new_row from (
        -- head_commit_row
        select hcr.row_id as row_id
        from ditty._get_head_commit_rows(_repository_id) hcr 

        except

        -- ...minus deleted rows
        select jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id as row_id
        from ditty.repository r
        where r.id = _repository_id

    ) remaining_rows

    union

    -- ...plus staged rows
    select jsonb_array_elements_text(r.stage_rows_to_add)::meta.row_id, true as new_row
    from ditty.repository r
    where r.id = _repository_id

$$ language sql;


-------------------------------------------------
-- Macro-ops
-------------------------------------------------

--
-- track_untracked_rows_by_relation
--

create or replace function _track_untracked_rows_by_relation( repository_id uuid, _relation_id meta.relation_id ) returns void as $$ -- returns setof uuid?
    update ditty.repository
    set tracked_rows_added = tracked_rows_added || (
        select jsonb_agg(row_id::text)
        from ditty._get_untracked_rows(_relation_id) row_id
    ) where id = repository_id;
$$ language sql;

create or replace function track_untracked_rows_by_relation( repository_name text, relation_id meta.relation_id ) returns void as $$ -- setof uuid?
    select ditty._track_untracked_rows_by_relation(ditty.repository_id(repository_name), relation_id);
$$ language sql;


--
-- stage_tracked_rows()
--

create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
declare
    _tracked_rows_obj jsonb;
begin
    -- append tracked_rows_added to stage_rows_to_add
    update ditty.repository
    set stage_rows_to_add = stage_rows_to_add || tracked_rows_added
    where id = _repository_id;

    -- clear repository.tracked_rows_added
    update ditty.repository set tracked_rows_added = '[]'::jsonb
    where id = _repository_id;

end;
$$ language plpgsql;

create or replace function stage_tracked_rows( repository_name text ) returns void as $$
    select ditty._stage_tracked_rows(ditty.repository_id(repository_name))
$$ language sql;


--
-- stage_updated_fields()
-- stages all changed unstaged field changes on a repository

create or replace function _stage_updated_fields( _repository_id uuid ) returns void as $$
    declare
        updated_fields jsonb;
    begin
        with updated_fields as (
            select jsonb_agg(f.field_id::text) field
            from ditty._get_offstage_updated_fields(_repository_id) f
        )
        update ditty.repository
        set stage_fields_to_change = stage_fields_to_change || updated_fields.field
        from updated_fields
        where id = _repository_id;

    end;
$$ language plpgsql;

create or replace function stage_updated_fields( repository_name text ) returns void as $$
    select ditty._stage_updated_fields(ditty.repository_id(repository_name));
$$ language sql;


--
-- stage_deleted_rows()
-- stage all off-stage deleted rows for removal
--

create or replace function _stage_deleted_rows( _repository_id uuid ) returns void as $$
    begin
        update ditty.repository
        set stage_rows_to_remove = stage_rows_to_remove || (
            select to_jsonb(array_agg(r::text)) lateral from ditty._get_offstage_deleted_rows (_repository_id) r
        )
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_deleted_rows( repository_name text ) returns void as $$
    select _stage_deleted_rows(ditty.repository_id(repository_name));
$$ language sql;

