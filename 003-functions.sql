------------------------------------------------------------------------------
-- REPOSITORY CREATE / DELETE
------------------------------------------------------------------------------
create or replace function repo_create( name text ) returns uuid as $$
    insert into delta.repo (name) values (name) returning id;
$$ language sql;

create or replace function repo_delete( _repo_id uuid ) returns void as $$
    -- TODO: delete blobs
    delete from delta.repo where id = _repo_id;
$$ language sql;


------------------------------------------------------------------------------
-- ROW TRACK / UNTRACK FUNCTIONS
------------------------------------------------------------------------------
-- track a row
create or replace function _track_row( repo_id uuid, row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        exists boolean;
    begin

        -- assert repo exists
        select true from delta.repo where id=repo_id into exists;
        if exists is not true then
            raise exception 'Repository with id % does not exist.', repo_id;
        end if;

        -- assert row exists
        if not meta.row_exists(row_id) then
            raise exception 'Row % does not exist.', row_id;
        end if;

        -- assert row is not already in a bundle or tracked or staged
        -- NOTE: unclear whether this constraint is desirable.  Can a row be tracked by more than one repo?

        insert into delta.tracked_row_added (repo_id, row_id)
        select id, row_id from delta.repo r where r.id = repo_id
        returning id into tracked_row_id;

        return tracked_row_id;
    end;
$$ language plpgsql;

create or replace function track_row( repo_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._track_row(
        id,
        meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
    )
    from delta.repo where name=repo_name;
$$ language sql;



-- untrack a row
create or replace function _untrack_row( row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        exists boolean;
    begin
        delete from delta.tracked_row_added tra where tra.row_id = _untrack_row.row_id
        returning id into tracked_row_id;

        if tracked_row_id is null then
            raise exception 'Row with row_id % is not tracked.', _untracked_row.row_id;
        end if;

        return tracked_row_id;
    end;
$$ language plpgsql;

create or replace function untrack_row( repo_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._untrack_row( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;



------------------------------------------------------------------------------
-- ROW STAGE / UNSTAGE FUNCTIONS
------------------------------------------------------------------------------

--
-- stage a row
--

create or replace function _stage_row( repo_id uuid, row_id meta.row_id ) returns uuid as $$
    declare
        tracked_row_id uuid;
        staged_row_id uuid;
        exists boolean;
    begin

        -- assert repo exists
        select true from delta._untrack_row(_stage_row.row_id) into exists;
        if exists != true then
            raise exception 'Repository with id % does not exist.', repo_id;
        end if;

        -- TODO: make sure the row is not already in the repo, or tracked by any other repo

        insert into delta.stage_row_added (repo_id, row_id) values ( _stage_row.repo_id, _stage_row.row_id)
        returning id into staged_row_id;

        return staged_row_id;
    end;
$$ language plpgsql;

create or replace function stage_row( repo_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._stage_row(
        r.id,
        meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
    )
    from delta.repo r where r.name=repo_name;
$$ language sql;


--
-- unstage a row
--

create or replace function _unstage_row( row_id meta.row_id ) returns uuid as $$
    declare
        staged_row_id uuid;
        exists boolean;
    begin

        -- assert row is staged in supplied repo
        select true from delta.stage_row_added sra where sra.row_id = _unstage_row.row_id into exists;
        if exists is not true then
            raise exception 'Row with row_id % is not staged.', row_id;
        end if;

        delete from delta.stage_row_added sra where sra.row_id = _unstage_row.row_id
        returning id into staged_row_id;

        return staged_row_id;
    end;
$$ language plpgsql;

create or replace function unstage_row( schema_name text, relation_name text, pk_column_name text, pk_value text )
returns uuid as $$
    select delta._unstage_row( meta.row_id(schema_name, relation_name, pk_column_name, pk_value));
$$ language sql;



------------------------------------------------------------------------------
-- COMMIT
------------------------------------------------------------------------------

/*
create function _commit( repository_id uuid, message text ) returns uuid as $$
    declare
        commit_id uuid;
    begin;

        insert into commit (name, message) values (name, message) 
        returning commit_id into _commit_id;


        insert into commit_row_added select * from stage_row_added where repo_id = _commit.repository_id;
        insert into commit_row_deleted
        insert into commit_field_changed

        delete from 
    end;
$$ language plpgsql;



create function commit( repository_name text, message text, author_name text, author_email text ) 
returns uuid as $$
    select _commit (id, message text, author_name, author_email)
    from delta.repository where name=repository_name;
$$ language sql;
*/




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

create or replace function commit_ancestry( _commit_id uuid ) returns uuid[] as $$
    with recursive parent as (
        select c.id, c.parent_id from commit c where c.id=_commit_id
        union
        select c.id, c.parent_id from commit c join parent p on c.id = p.parent_id
    ) select array_agg(id) from parent
    -- ancestors only
    where id != _commit_id;
$$ language sql;
