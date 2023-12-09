------------------------------------------------------------------------------
-- TRACK / UNTRACK ROW FUNCTIONS
------------------------------------------------------------------------------

--
-- track_row()
--

create or replace function _track_row( repository_id uuid, row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        exists boolean;
    begin

        -- assert repository exists
        if not delta._repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        -- assert row exists
        if not meta.row_exists(row_id) then
            raise exception 'Row with row_id % does not exist.', row_id;
        end if;

        -- assert row is not already in a bundle or tracked or staged
        -- NOTE: unclear whether this constraint is desirable.  Can a row be tracked by more than one repository?

        insert into delta.tracked_row_added (repository_id, row_id)
        select id, row_id from delta.repository r where r.id = repository_id
        returning id into tracked_row_id;

        return tracked_row_id;
    end;
$$ language plpgsql;


create or replace function track_row( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        tracked_row_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._track_row(
            delta._repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        ) into tracked_row_id;

        return tracked_row_id;
    end;
$$ language plpgsql;


--
-- untrack_row()
--

create or replace function _untrack_row( _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        exists boolean;
    begin
        delete from delta.tracked_row_added tra where tra.row_id = _row_id
        returning id into tracked_row_id;

        if tracked_row_id is null then
            raise exception 'Row with row_id % is not tracked.', _row_id;
        end if;

        return tracked_row_id;
    end;
$$ language plpgsql;

create or replace function untrack_row( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._untrack_row( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;
