set search_path=delta;

-- pff
create function _exmsg( message text ) returns text as $$
    select 'Δ💩: ' || message;
$$ language sql;

------------------------------------------------------------------------------
-- REPOSITORY FUNCTIONS
------------------------------------------------------------------------------
create or replace function repository_create( repository_name text ) returns uuid as $$
    insert into delta.repository (name) values (repository_name) returning id;
$$ language sql;

create or replace function _repository_delete( repository_id uuid ) returns void as $$
    begin
        if not _repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        delete from delta.repository where id = repository_id;
    end;
$$ language plpgsql;

create or replace function repository_delete( repository_name text ) returns void as $$
    begin
        if not repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        delete from delta.repository where name = repository_name;
    end;
$$ language plpgsql;

create or replace function repository_exists( _name text ) returns boolean as $$
    select exists (select 1 from delta.repository where name = _name);
$$ language sql;

create or replace function _repository_exists( repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.repository where id = repository_id);
$$ language sql;

create or replace function _repository_has_commits( _repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.commit where repository_id = _repository_id);
$$ language sql;

create or replace function _repository_id( name text ) returns uuid as $$
    select id from delta.repository where name= _repository_id.name;
$$ stable language sql;

------------------------------------------------------------------------------
-- ROW TRACK / UNTRACK FUNCTIONS
------------------------------------------------------------------------------
-- track a row
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



-- untrack a row
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



------------------------------------------------------------------------------
-- STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------

--
-- stage a row
--

create or replace function _stage_row( repository_id uuid, _row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        staged_row_id uuid;
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
        returning id into staged_row_id;

        return staged_row_id;
    end;
$$ language plpgsql;

create or replace function stage_row( repository_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    declare
        staged_row_id uuid;
    begin

        -- assert repository exists
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        select delta._stage_row(
            delta._repository_id(repository_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        ) into staged_row_id;

        return staged_row_id;
    end;
$$ language plpgsql;


--
-- unstage a row
--

create or replace function _unstage_row( _row_id meta.row_id ) returns uuid as $$
    declare
        staged_row_id uuid;
        row_exists boolean;
    begin

        -- assert row is staged
        select exists (select 1 from delta.stage_row_added sra where sra.row_id = _row_id) into row_exists;
        if not row_exists then
            raise exception 'Row with row_id % is not staged.', _row_id;
        end if;

        delete from delta.stage_row_added sra where sra.row_id = _row_id
        returning id into staged_row_id;

        return staged_row_id;
    end;
$$ language plpgsql;

create or replace function unstage_row( schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._unstage_row( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;


--
-- stage all tracked rows
--

create or replace function stage_tracked_rows( _repository_id uuid ) returns setof uuid as $$
    select delta._stage_row(repository_id, row_id) from delta.tracked_row_added tra where tra.repository_id = _repository_id;
$$ language sql;



--
-- stage a field change
--

--
-- unstage a field change
--



------------------------------------------------------------------------------
-- COMMIT
------------------------------------------------------------------------------

create function _commit(
    _repository_id uuid,
    message text,
    author_name text,
    author_email text,
    parent_commit_id uuid default null
) returns uuid as $$
    declare
        commit_id uuid;
        parent_commit_id uuid;
        first_commit boolean := false;
    begin
        if not delta._repository_exists(_repository_id) then
            raise exception 'Repository with id % does not exist.', _repository_id;
        end if;

        -- if no parent_commit_id is supplied, use head pointer
        if parent_commit_id is null then
            select head_commit_id from delta.repository where id = _repository_id into parent_commit_id;
        end if;

        -- if repository has no head commit and one is not supplied, either this is the first
        -- commit, or there is a problem
        if parent_commit_id is null then
            if delta._repository_has_commits(_repository_id) then
                raise exception 'No parent_commit_id supplied, and repository''s head_commit_id is null.  Please specify a parent commit_id for this commit.';
            else
                raise notice 'First commit!';
                first_commit := true;
            end if;
        end if;

        -- create the commit
        insert into delta.commit (
            repository_id,
            message,
            author_name,
            author_email,
            parent_id
        ) values (
            _repository_id,
            message,
            author_name,
            author_email,
            parent_commit_id
        )
        returning id into commit_id;

        -- update head pointer, checkout pointer
        update delta.repository set head_commit_id = commit_id, checkout_commit_id = commit_id;


        /*
        insert into commit_row_added select * from stage_row_added where repository_id = _commit.repository_id;
        insert into commit_row_deleted
        insert into commit_field_changed
        */

        return commit_id;
    end;
$$ language plpgsql;


create function commit(
    repository_name text,
    message text,
    author_name text,
    author_email text,
    parent_commit_id uuid default null
)
returns uuid as $$
    select delta._commit (id, message, author_name, author_email, parent_commit_id)
    from delta.repository where name=repository_name;
$$ language sql;


------------------------------------------------------------------------------
-- CHECKOUT
------------------------------------------------------------------------------

/*
create function checkout( _commit_id uuid ) returns text as $$
with recursive ancestry as (
    select c.id, c.parent_id, c.message, 1 as position from commit c where c.id = _commit_id
    union
    select c.id, c.parent_id, c.message, a.position+1 as position from commit c join ancestry a on c.id = a.parent_id
)
-- rows added
select ra.row_id
    from ancestry a
    join row_added ra on ra.commit_id = a.commit_id
    join row_deleted rd on rd.row_id = ra.ra.row_id on
except
-- rows deleted after they were added
select ra.row_id
    join row_deleted rd on
    from ancestry a
    join row_added ra on ra.commit_id = a.commit_id
return 'ok';
end
$$ language sql;
*/

-- from repo

create or replace function _commit_ancestry( _commit_id uuid ) returns uuid[] as $$
    with recursive parent as (
        select c.id, c.parent_id from commit c where c.id=_commit_id
        union
        select c.id, c.parent_id from commit c join parent p on c.id = p.parent_id
    ) select array_agg(id) from parent
    -- ancestors only
    where id != _commit_id;
$$ language sql;
