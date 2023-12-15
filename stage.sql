------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------

--
-- tables
--

create table stage_row_added (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id, -- TODO: check row_id.pk_values contains no nulls
    value jsonb,
    unique (repository_id, row_id)
);

create table stage_row_deleted (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id not null,
    unique (repository_id, row_id)
);

create table stage_field_changed (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id),
    field_id meta.field_id,
    value text,
    unique (repository_id, field_id)
);


-------------------------------------------------
-- Staging / Unstaging Functions
-------------------------------------------------

--
-- stage_row()
--

create or replace function _stage_row( repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        stage_row_added_id uuid;
        is_tracked boolean;
    begin

        -- assert repository exists
        if not delta._repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        if meta.row_exists(meta.row_id('delta','stage_row_added', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;

        /*
        -- done by untrack()
        if not meta.row_exists(meta.row_id('delta','tracked_row_added', 'row_id', row_id::text)) then
            raise exception 'Row with row_id % is not tracked.', row_id;
        end if;
        */

-- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform delta._untrack_row(_row_id);

        -- stage
        insert into delta.stage_row_added (repository_id, row_id) values ( repository_id, _row_id)
        returning id into stage_row_added_id;

        return stage_row_added_id;
    end;
$$ language plpgsql;

create or replace function stage_row( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        staged_row_added_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._stage_row(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        ) into staged_row_added_id;

        return staged_row_added_id;
    end;
$$ language plpgsql;


create or replace function stage_row( repository_name text, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns uuid as $$
    declare
        staged_row_added_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._stage_row(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_names, pk_values)
        ) into staged_row_added_id;

        return staged_row_added_id;
    end;
$$ language plpgsql;


--
-- unstage_row()
--

create or replace function _unstage_row( _row_id meta.row_id ) returns uuid as $$
    declare
        staged_row_added_id uuid;
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from delta.stage_row_added sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        delete from delta.stage_row_added sra where sra.row_id = _row_id
        returning id into staged_row_added_id;

        return staged_row_added_id;
    end;
$$ language plpgsql;

create or replace function unstage_row( schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._unstage_row( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;

create or replace function unstage_row( schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns uuid as $$
    select delta._unstage_row( meta.row_id(schema_name, relation_name, pk_column_names, pk_values));
$$ language sql;


--
-- delete row
--

create or replace function _delete_row( repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        stage_row_deleted_id uuid;
        is_tracked boolean;
    begin

        -- assert repository exists
        if not delta._repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        -- TODO: make sure the row is in the head commit

        -- stage
        insert into delta.stage_row_deleted (repository_id, row_id) values ( repository_id, _row_id)
        returning id into stage_row_deleted_id;

        return stage_row_deleted_id;
    end;
$$ language plpgsql;

create or replace function delete_row( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        stage_row_deleted_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._delete_row(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        ) into stage_row_deleted_id;

        return stage_row_deleted_id;
    end;
$$ language plpgsql;



--
-- stage a field change
--

--
-- unstage a field change
--



--
-- stage_tracked_rows()
--

create or replace function stage_tracked_rows( _repository_id uuid ) returns setof uuid as $$
    select delta._stage_row(repository_id, row_id) from delta.tracked_row_added tra where tra.repository_id = _repository_id;
$$ language sql;







-------------------------------------------------
-- Set Views / Functions
-------------------------------------------------

--
-- untracked_row
--

create or replace view untracked_row as
select r.row_id /*, r.row_id::meta.relation_id as relation_id */
from delta.exec((
    select array_agg (stmt) from delta.not_ignored_row_stmt
)) r (row_id meta.row_id)

where r.row_id::text not in ( -- TODO: yuck
    select a.row_id::text from delta.stage_row_added a
    union
    select t.row_id::text from delta.tracked_row_added t
    union
    select d.row_id::text from delta.stage_row_deleted d -- TODO: was: join rowset_row rr on d.rowset_row_id=rr.id
    union
    select row_id::text from delta.head_commit_row row_id
);


create or replace function tracked_rows( repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from delta.head_commit_row

    -- ...plus newly tracked rows
    union

    select tra.row_id
        from delta.repository r
            join delta.tracked_row_added tra on tra.repository_id=r.id

    -- plus staged rows
    union

    select sra.row_id
        from delta.repository r
            join delta.stage_row_added sra on sra.repository_id=r.id;
$$ language sql;


--
-- offstage_row_deleted
--

create or replace function offstage_row_deleted( _repository_id uuid ) returns setof meta.row_id as
$$
    select row_id
    from delta.db_head_commit_row(_repository_id)
        where exists = false

    except

    select srd.row_id
    from delta.stage_row_deleted srd where repository_id = _repository_id;
$$ language sql;


--
-- stage_row
--

create or replace function stage_rows( _repository_id uuid ) returns setof row_exists as $$
    select row_id, false as new_row from (
        -- head_commit_row
        select hcr.row_id
        from repository r
            join delta.head_commit_row hcr on hcr.repository_id = r.id
        where r.id = _repository_id


        except

        -- ...minus deleted rows
        select row_id
        from stage_row_deleted
        where repository_id = _repository_id
    ) remaining_rows

    union

    -- ...plus staged rows
    select sra.row_id, true as new_row
    from delta.stage_row_added sra
    where sra.repository_id = _repository_id

$$ language sql;


--
-- stage_row_field
--


--
-- get_stage_rows_exist
--
