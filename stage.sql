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
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- check that it's not already staged
        if meta.row_exists(meta.row_id('delta','stage_row_to_add', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;

        -- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform delta._untrack_tracked_row(_repository_id, _row_id);

        -- stage
        update delta.repository
        -- set stage_rows_to_add = stage_rows_to_add || jsonb_build_object(_row_id::text, delta._get_db_row_field_hashes_obj(_row_id))
        set stage_rows_to_add = stage_rows_to_add || to_jsonb(_row_id::text)
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_tracked_row( repository_name text, row_id meta.row_id )
returns void as $$
    begin
        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._stage_tracked_row(
            delta.repository_id(repository_name),
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
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- TODO: make sure the row is in the head commit

        -- stage
        update delta.repository
        set stage_rows_to_remove = stage_rows_to_remove || to_jsonb(_row_id::text)
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_to_remove( repository_name text, row_id meta.row_id )
returns void as $$
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._stage_row_to_remove(
            delta.repository_id(repository_name),
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
        select exists (select 1 from delta.stage_row_to_add sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        -- TODO: fix.
        update delta.repository
        set stage_rows_to_remove = stage_rows_to_remove - array[_row_id::text]
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function unstage_row_to_remove( _repository_id uuid, row_id meta.row_id )
returns void as $$
    select delta._unstage_row_to_remove(_repository_id, row_id);
$$ language sql;


--
-- stage a field change
--

create or replace function _stage_field_to_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
    begin
        -- TODO: assert field is changed and part of repo
        update delta.repository
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
        update delta.repository set stage_rows_to_add = '[]' where id = _repository_id;
        update delta.repository set stage_rows_to_remove = '[]' where id = _repository_id;
        update delta.repository set stage_fields_to_change = '[]' where id = _repository_id;
    end;
$$ language plpgsql;




-------------------------------------------------
-- Set Views / Functions
-- Convention: _get_*()
-------------------------------------------------

--
-- get_stage_rows_to_add()
--

create or replace function _get_stage_rows_to_add( _repository_id uuid ) returns table (repository_id uuid,row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(stage_rows_to_add)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_add as
select id as repository_id, jsonb_array_elements_text(stage_rows_to_add)::meta.row_id as row_id
from delta.repository;


--
-- get_stage_rows_to_remove()
--

create or replace function _get_stage_rows_to_remove( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_to_remove as
select id as repository_id, jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id as row_id
from delta.repository;


--
-- get_stage_fields_to_change()
--

create or replace function _get_stage_fields_to_change( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements_text(stage_fields_to_change)::meta.field_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_field_to_change as
select id as repository_id, jsonb_array_elements_text(stage_fields_to_change)::meta.field_id as field_id
from delta.repository;


--
-- _is_staged()
--

create or replace function _is_staged( repository_id uuid, row_id meta.row_id ) returns boolean as $$
begin
    return (
        select jsonb_array_elements_text(stage_rows_to_add) = row_id::text
        from delta.repository
        where id = repository_id
    );
end;
$$ language plpgsql;



--
-- get_tracked_rows()
-- Returns *all* tracked rows: Newly tracked, staged and head_commit rows

create or replace function _get_tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from delta._get_head_commit_rows(_repository_id)

    -- ...plus newly tracked rows
    union

    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id
    from delta.repository r
    where r.id = _repository_id

    -- plus staged rows
    union

    select jsonb_array_elements_text(r.stage_rows_to_add)::meta.row_id
    from delta.repository r
    where r.id = _repository_id
$$ language sql;

create or replace function get_tracked_rows( repository_name text ) returns setof meta.row_id as $$
    select delta._get_tracked_rows(
        delta.repository_id(repository_name)
    );
$$ language sql;



--
-- stage_deleted_rows() TODO
--



create or replace function _get_offstage_deleted_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- rows deleted from head commit
    select row_id
    from delta._get_db_head_commit_rows(_repository_id)
        where exists = false

    except

    -- minus those that have been staged for deletion
    select jsonb_array_elements_text(r.stage_rows_to_remove)::meta.row_id
    from delta.repository r where r.id = _repository_id;
$$ language sql;


--
-- get_stage_updated_fields() TODO
--

--
-- get_offstage_updated_fields()
--

create or replace function _get_offstage_updated_fields( _repository_id uuid ) returns setof delta.field_hash as $$
    -- rows deleted from head commit
    select *
    from delta._get_db_head_commit_fields(_repository_id)

    except

    -- minus those that have been staged for deletion
    select *
    from delta._get_head_commit_fields(_repository_id)

$$ language sql;


--
-- _get_stage_rows()
--

create type stage_row as (row_id meta.row_id, new_row boolean);
create or replace function _get_stage_rows( _repository_id uuid ) returns setof stage_row as $$
    select row_id, false as new_row from (

/*
        -- head_commit_row
        select hcr.row_id as row_id
        from delta.get_head_commit_rows(_repository_id) hcr 

        except
        */

        -- ...minus deleted rows
        select jsonb_array_elements_text(stage_rows_to_remove)::meta.row_id as row_id
        from delta.repository r
        where r.id = _repository_id

    ) remaining_rows

    union

    -- ...plus staged rows
    select jsonb_array_elements_text(r.stage_rows_to_add)::meta.row_id, true as new_row
    from delta.repository r
    where r.id = _repository_id

$$ language sql;


-------------------------------------------------
-- Macro-ops
-------------------------------------------------

--
-- track_untracked_rows_by_relation
--

create or replace function _track_untracked_rows_by_relation( repository_id uuid, _relation_id meta.relation_id ) returns void as $$ -- returns setof uuid?
    update delta.repository
    set tracked_rows_added = tracked_rows_added || (
        select jsonb_agg(row_id::text)
        from delta._get_untracked_rows(_relation_id) row_id
    ) where id = repository_id;
$$ language sql;

create or replace function track_untracked_rows_by_relation( repository_name text, relation_id meta.relation_id ) returns void as $$ -- setof uuid?
    select delta._track_untracked_rows_by_relation(delta.repository_id(repository_name), relation_id);
$$ language sql;


--
-- stage_tracked_rows()
--

-- TODO: this can probably be optimized by combining calls to get_db_row_fields_obj()
create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
declare
    _tracked_rows_obj jsonb;
begin
    /*
    OLD: obj-based approach
    -- create _tracked_rows_obj
    select jsonb_object_agg(r.row_id, delta._get_db_row_field_hashes_obj(row_id::meta.row_id))
    into _tracked_rows_obj
    from (
        select jsonb_array_elements_text(tracked_rows_added) row_id
        from delta.repository where id = _repository_id
    ) r;

    -- append _tracked_rows_obj to stage_rows_to_add
    update delta.repository
    set stage_rows_to_add = stage_rows_to_add || _tracked_rows_obj
    where id = _repository_id;
    */

    update delta.repository
    set stage_rows_to_add = stage_rows_to_add || tracked_rows_added
    where id = _repository_id;

    -- clear repository.tracked_rows_added
    -- TODO: function for this
    update delta.repository set tracked_rows_added = '[]'::jsonb
    where id = _repository_id;

end;
$$ language plpgsql;

create or replace function stage_tracked_rows( repository_name text ) returns void as $$
    select delta._stage_tracked_rows(delta.repository_id(repository_name))
$$ language sql;


--
-- stage_updated_fields()
-- stages all changed unstaged field changes on a repository

create or replace function _stage_updated_fields( _repository_id uuid ) returns void as $$
    -- TODO: rewrite
    begin
        update delta.repository
        set stage_fields_to_change = stage_fields_to_change || (
            select jsonb_object_agg( field_id::text, value_hash ) from _get_offstage_updated_fields(_repository_id)
        )
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_updated_fields( repository_name text ) returns void as $$
    select delta._stage_updated_fields(delta.repository_id(repository_name));
$$ language sql;


--
-- stage_deleted_rows()
-- stage all off-stage deleted rows for removal
--

create or replace function _stage_deleted_rows( _repository_id uuid ) returns void as $$
    begin
        update delta.repository
        set stage_rows_to_remove = stage_rows_to_remove || (
            select to_jsonb(array_agg(r::text)) lateral from _get_offstage_deleted_rows (_repository_id) r
        )
        where id = _repository_id;
    end;
$$ language plpgsql;
