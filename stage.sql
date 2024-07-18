------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------

--
-- tables
--

/*
create table stage_row_added (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id, -- TODO: check row_id.pk_values contains no nulls
    unique (repository_id, row_id)
);
create index stage_row_added_row_id_schema_name on stage_row_added using hash(((row_id).schema_name));
create index stage_row_added_row_id_relation_name on stage_row_added using hash(((row_id).relation_name));


create table stage_row_deleted (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id not null,
    unique (repository_id, row_id)
);
create index stage_row_deleted_row_id_schema_name on stage_row_deleted using hash (((row_id).schema_name));
create index stage_row_deleted_row_id_relation_name on stage_row_deleted using hash (((row_id).relation_name));


create table stage_row_untracked (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id not null,
    unique (repository_id, row_id)
);
create index stage_row_untracked_row_id_schema_name on stage_row_untracked using hash (((row_id).schema_name));
create index stage_row_untracked_row_id_relation_name on stage_row_untracked using hash (((row_id).relation_name));


create table stage_field_changed (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id),
    field_id meta.field_id,
    unique (repository_id, field_id)
);
create index stage_field_changed_field_id_schema_name on stage_field_changed using hash (((field_id).schema_name));
create index stage_field_changed_field_id_relation_name on stage_field_changed using hash (((field_id).relation_name));
create index stage_field_changed_field_id_column_name on stage_field_changed using hash (((field_id).column_name));
*/



-------------------------------------------------
-- Staging / Unstaging Functions
-------------------------------------------------

--
-- stage_row_add()
--

create or replace function _stage_row_add( _repository_id uuid, _row_id meta.row_id ) returns void as $$
    declare
        stage_row_added_id uuid;
    begin

        -- assert repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        /*
        -- check that it's not already staged
        if meta.row_exists(meta.row_id('delta','stage_row_added', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;
        */

        -- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform delta._tracked_row_delete(_row_id);

        -- stage
        update delta.repository set stage = stage || '{"rows_added": "' || row_id::text || '"}'::jsonb
        where id = _repository_id;
    end;
$$ language plpgsql;

create or replace function stage_row_add( repository_name text, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns void as $$
    declare
        stage_row_added_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._stage_row_add(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_names, pk_values)
        ) into stage_row_added_id;
    end;
$$ language plpgsql;

-- helper for single column pks
create or replace function stage_row_add( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text ) returns void as $$
    select delta.stage_row_add(repository_name, schema_name, relation_name, array[pk_column_name], array[pk_value]);
$$ language sql;



--
-- stage_row_delete()
--

create or replace function _stage_row_remove( _row_id meta.row_id ) returns void as $$
    declare
        stage_row_added_id uuid;
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from delta.stage_row_added sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        delete from delta.stage_row_added sra where sra.row_id = _row_id
        returning id into stage_row_added_id;
    end;
$$ language plpgsql;

create or replace function stage_row_remove( schema_name text, relation_name text, pk_column_name text, pk_value text )
returns void as $$
    select delta._stage_row_remove( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;

create or replace function stage_row_remove( schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns void as $$
    select delta._stage_row_remove( meta.row_id(schema_name, relation_name, pk_column_names, pk_values));
$$ language sql;


--
-- delete row
--

create or replace function _stage_row_delete( repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        stage_row_deleted_id uuid;
    begin

        -- assert repository exists
        if not delta._repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        -- TODO: make sure the row is in the head commit

        -- stage
        insert into delta.stage_row_deleted (repository_id, row_id) values (repository_id, _row_id)
        returning id into stage_row_deleted_id;

        return stage_row_deleted_id;
    end;
$$ language plpgsql;

create or replace function stage_row_delete( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        stage_row_deleted_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._stage_row_delete(
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



-------------------------------------------------
-- Set Views / Functions
-------------------------------------------------

--
-- untracked_row
--

/*
create or replace view untracked_row as
-- all rows in trackable_relations
select r.row_id from delta.exec((select array_agg (stmt) from delta.not_ignored_row_stmt)) r (row_id meta.row_id)

except

select * from (
    select a.row_id from delta.stage_row_added a
    union
    select t.row_id from delta.tracked_row_added t
    union
    select d.row_id from delta.stage_row_deleted d
    union
    select row_id from delta.head_commit_row row_id
);
*/


create function untracked_rows(_relation_id meta.relation_id default null) returns setof meta.row_id as $$
select r.row_id
from delta.exec((
    select array_agg (stmt)
    from delta.not_ignored_row_stmt
    where relation_id = coalesce(_relation_id, relation_id)
)) r (row_id meta.row_id)

except

select * from (
    select jsonb_array_elements_text(r.stage->'rows_added')::meta.row_id from delta.repository r -- where relation_id=....?
    union
    -- select t.row_id from delta.tracked_row_added t
    select jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id from delta.repository r -- where relation_id=....?
    union
    -- select d.row_id from delta.stage_row_deleted d
    select jsonb_array_elements_text(r.stage->'rows_deleted')::meta.row_id from delta.repository r-- where relation_id=....?

    /*
    TO RESURRECT:
    union
    select row_id from delta.head_commit_row row_id
    */
) r;
$$ language sql;


--
-- tracked_rows
--

create or replace function tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select /* TO RESURRECT: row_id from delta.head_commit_row
    where repository_id = _repository_id

    -- ...plus newly tracked rows
    union

    select */ jsonb_array_elements_text(r.tracked_rows_added)::meta.row_id
    from delta.repository r
    where r.id = _repository_id

    -- plus staged rows
    union

    select jsonb_array_elements_text(r.stage->'rows_added')::meta.row_id
    from delta.repository r
    where r.id = _repository_id
$$ language sql;


--
-- offstage_row_deleted
--

create or replace function offstage_row_deleted( _repository_id uuid ) returns setof meta.row_id as $$
    -- rows deleted from head commit
    select row_id
    from delta.db_head_commit_rows(_repository_id)
        where exists = false

    except

    -- minus those that have been staged for deletion
    select jsonb_array_elements_text(r.stage->'rows_deleted')::meta.row_id
    from delta.repository r where r.id = _repository_id;
$$ language sql;


--
-- stage_rows
--

create type stage_row as (row_id meta.row_id, new_row boolean);
create or replace function stage_rows( _repository_id uuid ) returns setof stage_row as $$
    select row_id, false as new_row from (

        -- head_commit_row
        select hcr.row_id
        from delta.head_commit_rows(_repository_id) hcr 

        except

        -- ...minus deleted rows
        select jsonb_array_elements_text(r.stage->'rows_deleted')::meta.row_id
        from delta.repository r
        where r.id = _repository_id

    ) remaining_rows

    union

    -- ...plus staged rows
    select jsonb_array_elements_text(r.stage->'rows_added')::meta.row_id, true as new_row
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

/*
TO RESURRECT:

create or replace function _track_relation_rows( repository_id uuid, _relation_id meta.relation_id ) returns void as $$ -- returns setof uuid?
    insert into delta.tracked_row_added(repository_id, row_id)
    select repository_id, row_id
    from delta.untracked_rows(_relation_id) row_id
--    returning id
$$ language sql;

create or replace function track_relation_rows( repository_name text, schema_name text, relation_name text ) returns void as $$ -- setof uuid?
    select delta._track_relation_rows(delta.repository_id(repository_name), meta.relation_id(schema_name, relation_name));
$$ language sql;


--
-- stage_tracked_rows()
--

create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
begin
    insert into delta.stage_row_added (repository_id, row_id)
    select repository_id, row_id from delta.tracked_row_added
    where repository_id = _repository_id;

    -- delete all tracked rows for this repo
    delete from delta.tracked_row_added
    where repository_id = _repository_id;
end;
$$ language plpgsql;

create or replace function stage_tracked_rows( repository_name text ) returns void as $$
    select delta._stage_tracked_rows(delta.repository_id(repository_name))
$$ language sql;
*/
