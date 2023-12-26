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


create table stage_field_changed (
    id uuid not null default public.uuid_generate_v7() primary key,
    repository_id uuid not null references repository(id),
    field_id meta.field_id,
    value text,
    unique (repository_id, field_id)
);
create index stage_field_changed_field_id_schema_name on stage_field_changed using hash (((field_id).schema_name));
create index stage_field_changed_field_id_relation_name on stage_field_changed using hash (((field_id).relation_name));
create index stage_field_changed_field_id_column_name on stage_field_changed using hash (((field_id).column_name));



-------------------------------------------------
-- Staging / Unstaging Functions
-------------------------------------------------

--
-- staged_row_add()
--

create or replace function _staged_row_add( _repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        stage_row_added_id uuid;
        is_tracked boolean;
    begin

        -- assert repository exists
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        if meta.row_exists(meta.row_id('delta','stage_row_added', 'row_id', _row_id::text)) then
            raise exception 'Row with row_id % is already staged.', _row_id;
        end if;

-- TODO: make sure the row is not already in the repository, or tracked by any other repo

        -- untrack
        perform delta._tracked_row_remove(_row_id);

        -- stage
        execute format('
            insert into delta.stage_row_added (repository_id, row_id, value)
            select %L, %L, to_jsonb(x)
            from %I.%I x where %s
            returning id',
            _repository_id,
            _row_id,
            _row_id.schema_name,
            _row_id.relation_name,
            meta._pk_stmt(_row_id, '%1$I = %2$L')
        ) into stage_row_added_id;


        return stage_row_added_id;
    end;
$$ language plpgsql;

create or replace function staged_row_add( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        staged_row_added_id uuid;
    begin
        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._staged_row_add(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        ) into staged_row_added_id;

        return staged_row_added_id;
    end;
$$ language plpgsql;


create or replace function staged_row_add( repository_name text, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns uuid as $$
    declare
        staged_row_added_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._staged_row_add(
            delta.repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_names, pk_values)
        ) into staged_row_added_id;

        return staged_row_added_id;
    end;
$$ language plpgsql;


--
-- staged_row_remove()
--

create or replace function _staged_row_remove( _row_id meta.row_id ) returns uuid as $$
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

create or replace function staged_row_remove( schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._staged_row_remove( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;

create or replace function staged_row_remove( schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
returns uuid as $$
    select delta._staged_row_remove( meta.row_id(schema_name, relation_name, pk_column_names, pk_values));
$$ language sql;


--
-- delete row
--

create or replace function _stage_row_delete( repository_id uuid, _row_id meta.row_id ) returns uuid as $$
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


create function untracked_rows(_relation_id meta.relation_id default null) returns setof meta.row_id as $$
select r.row_id
from delta.exec((
    select array_agg (stmt)
    from delta.not_ignored_row_stmt
    where relation_id = coalesce(_relation_id, relation_id)
)) r (row_id meta.row_id)

except

select * from (
    select a.row_id from delta.stage_row_added a -- where relation_id=....?
    union
    select t.row_id from delta.tracked_row_added t
    union
    select d.row_id from delta.stage_row_deleted d
    union
    select row_id from delta.head_commit_row row_id
);
$$ language sql;


create or replace function _rel_row_template( relation_generator_stmt text, action_stmt text, delimiter text ) returns text as $$
declare
    rel meta.relation_id;
    action_stmts text[];
    i integer = 0;
begin
    for rel in execute relation_generator_stmt loop
        action_stmts := array_append(action_stmts, format(action_stmt, rel.schema_name, rel.name, i));
        i = i + 1;
    end loop;

    return array_to_string(action_stmts, delimiter);
end
$$ language plpgsql;


--
-- tracked_rows
--

create or replace function tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
    -- head commit rows
    select row_id from delta.head_commit_row where repository_id = _repository_id

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

create or replace function offstage_row_deleted( _repository_id uuid ) returns setof meta.row_id as $$
    select row_id
    from delta.db_head_commit_rows(_repository_id)
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
        from delta.repository r
            join delta.head_commit_row hcr on hcr.repository_id = r.id
        where r.id = _repository_id


        except

        -- ...minus deleted rows
        select row_id
        from delta.stage_row_deleted
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




-------------------------------------------------
-- Macro-ops
-------------------------------------------------

--
-- track_relation_rows
--

create or replace function _track_relation_rows( repository_id uuid, _relation_id meta.relation_id ) returns setof uuid as $$
    insert into delta.tracked_row_added(repository_id, row_id)
    select repository_id, row_id
    from delta.untracked_rows(_relation_id) row_id
    returning id
$$ language sql;

create or replace function track_relation_rows( repository_name text, schema_name text, relation_name text ) returns setof uuid as $$
    select delta._track_relation_rows(delta.repository_id(repository_name), meta.relation_id(schema_name, relation_name));
$$ language sql;


--
-- stage_tracked_rows()
--

create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
declare
    rel record;
    stmt text;
begin
   --  select delta._staged_row_add(repository_id, row_id) from delta.tracked_row_added tra where tra.repository_id = _repository_id;
   -- ^^ SLOW! Speed up by: bypass row_exists, one insert stmt per relation

    -- all relations in tracked_row_added
    for rel in
        select distinct
            (tra.row_id).schema_name,
            (tra.row_id).relation_name,
            (tra.row_id).pk_column_names
        from delta.tracked_row_added tra
        where repository_id = _repository_id
    loop
        -- insert the row with its current value into stage_row_added
        stmt := format('
        insert into delta.stage_row_added(repository_id, row_id, value)
        select repository_id, row_id, to_jsonb(x)
        from delta.tracked_row_added tra
            join %1$I.%2$I x on %4$s
        where
            (tra.row_id).schema_name = %1$L and
            (tra.row_id).relation_name = %2$L and
            tra.repository_id=%L',
            rel.schema_name,
            rel.relation_name,
            _repository_id,
            meta._pk_stmt(
                rel.pk_column_names,
                rel.pk_column_names, -- no values, not needed
                'x.%1$I::text = (tra.row_id).pk_values[%3$s]', ' and '
            )
        );

        raise debug 'stmt: %', stmt;
        execute stmt;
    end loop;

    -- delete all tracked rows for this repo
    delete from delta.tracked_row_added
    where repository_id = _repository_id;
end;
$$ language plpgsql;

create or replace function stage_tracked_rows( repository_name text ) returns void as $$
    select delta._stage_tracked_rows(delta.repository_id(repository_name))
$$ language sql;
