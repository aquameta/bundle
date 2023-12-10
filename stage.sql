------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------

--
--
-- tables
--
--

create table stage_row_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id,
    value jsonb,
    unique (repository_id, row_id)
);

create table stage_row_deleted (
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id not null,
    unique (repository_id, row_id)
);

create table stage_field_changed (
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id),
    field_id meta.field_id,
    value text,
    unique (repository_id, field_id)
);

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
            delta._repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
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
            delta._repository_id(repository_name),
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



