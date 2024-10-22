------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------


-------------------------------------------------
-- Staging / Unstaging Action Functions
-------------------------------------------------

--
-- stage_row_add()
--

create or replace function _stage_row_add( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    begin
        -- assert repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- check that it's not already staged
        /*
        if meta.row_exists(meta.row_id('delta','stage_row_added', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;
        */

        -- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform delta._tracked_row_remove(_repository_id, _row_id);

        -- stage
        update delta.repository
        set stage_rows_added = stage_rows_added || jsonb_build_object(_row_id::text, delta.db_row_field_hashes_obj(_row_id))
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_add( repository_name text, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns void as $$
    begin
        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._stage_row_add(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_names, pk_values)
        );
    end;
$$ language plpgsql;

-- helper for single column pks
create or replace function stage_row_add( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text ) returns void as $$
    select delta.stage_row_add(repository_name, schema_name, relation_name, array[pk_column_name], array[pk_value]);
$$ language sql;



--
-- stage_row_delete()
--

create or replace function _stage_row_delete( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
    begin

        -- assert repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- TODO: make sure the row is in the head commit

        -- stage
        update delta.repository set stage_rows_deleted = stage_rows_deleted || to_jsonb(_row_id::text)
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_delete( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns void as $$
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._stage_row_delete(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        );
    end;
$$ language plpgsql;


--
-- unstage_row()
--
-- Removes a staged row (add or delete) from the stage.  Split these up?

create or replace function _unstage_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from delta.stage_row_added sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        update delta.repository set stage_rows_added = stage_rows_added - array[_row_id::text]
        where id = _repository_id;

        update delta.repository set stage_rows_deleted = stage_rows_deleted - array[_row_id::text]
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns void as $$
    select delta._unstage_row(_repository_id, meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;

create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns void as $$
    select delta._unstage_row(_repository_id, meta.row_id(schema_name, relation_name, pk_column_names, pk_values));
$$ language sql;


--
-- stage a field change
--

create or replace function _stage_field_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
    begin
        -- TODO: asert field is changed and part of repo
        update delta.repository
        set stage_fields_changed = stage_fields_changed || jsonb_build_object(_field_id::text, meta.field_id_literal_value(_field_id))
        where id = _repository_id;
        return true;
    end;
$$ language plpgsql;

--
-- unstage a field change
--


-------------------------------------------------
-- Set Views / Functions
-- Convention: _get_*()
-------------------------------------------------
--
-- stage_rows_added()
--

create or replace function _stage_rows_added( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_object_keys(stage_rows_added)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_added as
select id as repository_id, jsonb_object_keys(stage_rows_added)::meta.row_id as row_id
from delta.repository;


--
-- stage_rows_deleted()
--

create or replace function _stage_rows_deleted( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_array_elements(stage_rows_deleted)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_row_deleted as
select id as repository_id, jsonb_array_elements(stage_rows_deleted)::meta.row_id as row_id
from delta.repository;


--
-- stage_fields_changed()
--

create or replace function _get_stage_fields_changed( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
    select id, jsonb_object_keys(stage_fields_changed)::meta.row_id
    from delta.repository
    where id = _repository_id;
$$ language sql;

create view stage_field_changed as
select id as repository_id, jsonb_object_keys(stage_fields_changed)::meta.field_id as field_id
from delta.repository;


--
-- _is_staged()
--

create or replace function _is_staged( row_id meta.row_id ) returns boolean as $$
declare
    row_count integer;
begin
    select count(*) into row_count from delta.repository where jsonb_object_keys(stage_rows_added)::text ? row_id::text;
    if row_count > 0 then
        return true;
    else
        return false;
    end if;
end;
$$ language plpgsql;




---------- end new paste






--
-- untracked_rows
--

create or replace function untracked_rows(_relation_id meta.relation_id default null) returns setof meta.row_id as $$
-- all rows that aren't ignored by an ignore rule
select r.row_id
from delta.exec((
    select array_agg (stmt)
    from delta.not_ignored_row_stmt
    where relation_id = coalesce(_relation_id, relation_id)
)) r (row_id meta.row_id)

except

-- ...except the following:
select * from (
    -- stage_rows_added
    select jsonb_object_keys(r.stage_rows_added)::meta.row_id from delta.repository r -- where relation_id=....?

    union
    -- tracked rows
    -- select t.row_id from delta.tracked_row_added t
    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id from delta.repository r -- where relation_id=....?

    union
    -- stage_rows_deleted
    -- select d.row_id from delta.stage_row_deleted d
    select jsonb_array_elements_text(r.stage_rows_deleted)::meta.row_id from delta.repository r-- where relation_id=....?

    union
    -- head_commit_rows for all tables
    select hcr.row_id as row_id
    from delta.repository r, delta._head_commit_rows(r.id) hcr
) r;
$$ language sql;


--
-- tracked_rows
--

create or replace function tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from delta._head_commit_rows(_repository_id)

    -- ...plus newly tracked rows
    union

    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id
    from delta.repository r
    where r.id = _repository_id

    -- plus staged rows
    union

    select jsonb_object_keys(r.stage_rows_added)::meta.row_id
    from delta.repository r
    where r.id = _repository_id
$$ language sql;


--
-- offstage_rows_deleted
--

create or replace function _offstage_rows_deleted( _repository_id uuid ) returns setof meta.row_id as $$
    -- rows deleted from head commit
    select row_id
    from delta._db_head_commit_rows(_repository_id)
        where exists = false

    except

    -- minus those that have been staged for deletion
    select jsonb_array_elements_text(r.stage_rows_deleted)::meta.row_id
    from delta.repository r where r.id = _repository_id;
$$ language sql;


--
-- offstage_fields_changed()
--

create or replace function _offstage_fields_changed( _repository_id uuid ) returns setof delta.field_hash as $$
    -- rows deleted from head commit
    select *
    from delta._db_head_commit_fields(_repository_id)

    except

    -- minus those that have been staged for deletion
    select *
    from delta._head_commit_fields(_repository_id)

$$ language sql;


--
-- stage_rows()
--

create type stage_row as (row_id meta.row_id, new_row boolean);
create or replace function stage_rows( _repository_id uuid ) returns setof stage_row as $$
    select row_id, false as new_row from (

/*
        -- head_commit_row
        select hcr.row_id as row_id
        from delta.head_commit_rows(_repository_id) hcr 

        except
        */

        -- ...minus deleted rows
        select jsonb_array_elements_text(stage_rows_deleted)::meta.row_id as row_id
        from delta.repository r
        where r.id = _repository_id

    ) remaining_rows

    union

    -- ...plus staged rows
    select jsonb_object_keys(r.stage_rows_added)::meta.row_id, true as new_row
    from delta.repository r
    where r.id = _repository_id

$$ language sql;


--
-- stage_row_field
--




-------------------------------------------------
-- Macro-ops
-------------------------------------------------

--
-- track_relation_rows
--

create or replace function _track_relation_rows( repository_id uuid, _relation_id meta.relation_id ) returns void as $$ -- returns setof uuid?
    update delta.repository
    set tracked_rows_added = tracked_rows_added || (
        select jsonb_agg(row_id::text)
        from delta.untracked_rows(_relation_id) row_id
    ) where id = repository_id;
$$ language sql;

create or replace function track_relation_rows( repository_name text, schema_name text, relation_name text ) returns void as $$ -- setof uuid?
    select delta._track_relation_rows(delta.repository_id(repository_name), meta.relation_id(schema_name, relation_name));
$$ language sql;


--
-- stage_tracked_rows()
--

-- TODO: this can probably be optimized by combining calls to db_row_fields_obj()
create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
declare
    _tracked_rows_obj jsonb;
begin
    -- create _tracked_rows_obj
    select jsonb_object_agg(r.row_id, delta.db_row_field_hashes_obj(row_id::meta.row_id))
    into _tracked_rows_obj
    from (
        select jsonb_array_elements_text(tracked_rows_added) row_id
        from delta.repository where id = _repository_id
    ) r;

    -- append _tracked_rows_obj to stage_rows_added
    update delta.repository
    set stage_rows_added = stage_rows_added || _tracked_rows_obj
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
-- stage_fields_changed()
-- stages all changed unstaged field changes on a repository

create or replace function _stage_fields_changed( _repository_id uuid ) returns void as $$
    begin
        update delta.repository
        set stage_fields_changed = stage_fields_changed || (
            select jsonb_object_agg( field_id::text, value_hash ) from _offstage_fields_changed(_repository_id)
        )
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_fields_changed( repository_name text ) returns void as $$
    select _stage_fields_changed(delta.repository_id(repository_name));
$$ language sql;
