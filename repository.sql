------------------------------------------------------------------------------
-- DATA MODEL
------------------------------------------------------------------------------

--
-- blob
--

create table blob (
    hash text primary key not null,
    value text,
    unique(hash, value)
);
create index blob_hash_hash_index on blob using hash (hash);


create or replace function blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value is NULL then
            NEW.hash = '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9'::bytea;
            return NEW;
        end if;

        NEW.hash = delta.hash(NEW.value);
        if exists (select 1 from delta.blob b where b.hash = NEW.hash) then
            return NULL;
        end if;

        return NEW;
    end;
$$ language plpgsql;

create trigger blob_hash_update
    before insert or update on blob
    for each row execute procedure blob_hash_gen_trigger();


--
-- commit
--

create table commit (
    id uuid not null default public.uuid_generate_v7() primary key,
    parent_id uuid references commit(id), --null means first commit
    merge_parent_id uuid references commit(id),

    manifest jsonb not null,

    author_name text not null default '',
    author_email text not null default '',
    message text not null default '',
    commit_time timestamptz not null default now()
);
-- TODO: check constraint for only one null parent_id per repo
-- TODO: i am not my own grandpa


--
-- repository
--

create table repository (
    id uuid not null default public.uuid_generate_v7() primary key,
    name text not null unique check(name != ''),
    head_commit_id uuid unique references commit(id) on delete set null deferrable initially deferred,
    checkout_commit_id uuid unique references commit(id) on delete set null deferrable initially deferred,

    tracked_rows_added jsonb not null default '[]',

    stage_rows_added jsonb not null default '{}',
    stage_rows_deleted jsonb not null default '[]',
    stage_fields_changed jsonb not null default '{}'
);
-- TODO: stage_commit can't be checkout_commit or head_commit

-- circular fk
alter table commit add column repository_id uuid /* not null FIXME why is deferrable not working?? */ references repository(id) on delete cascade deferrable initially deferred;


------------------------------------------------------------------------------
-- FUNCTIONS
------------------------------------------------------------------------------

--
-- id()
--

create or replace function repository_id( repository_name text ) returns uuid as $$
    select id from delta.repository where name=repository_name;
$$ stable language sql;


--
-- repository_name()
--

create or replace function _repository_name( repository_id uuid ) returns text as $$
    select name from delta.repository where id=repository_id;
$$ stable language sql;


--
-- stage_commit_id()
--

/*
MOVED TO repo.stage
create or replace function _stage_commit_id( repository_id uuid ) returns uuid as $$
    select stage_commit_id from delta.repository where id=repository_id;
$$ stable language sql;

create or replace function stage_commit_id( repository_name text ) returns uuid as $$
    select stage_commit_id from delta.repository where name=repository_name;
$$ stable language sql;
*/


--
-- head_commit_id()
--

create or replace function _head_commit_id( repository_id uuid ) returns uuid as $$
    select head_commit_id from delta.repository where id=repository_id;
$$ stable language sql;

create or replace function head_commit_id( repository_name text ) returns uuid as $$
    select head_commit_id from delta.repository where name=repository_name;
$$ stable language sql;



--
-- checkout_commit_id()
--

create or replace function _checkout_commit_id( repository_id uuid ) returns uuid as $$
    select checkout_commit_id from delta.repository where id=repository_id;
$$ stable language sql;

create or replace function checkout_commit_id( repository_name text ) returns uuid as $$
    select checkout_commit_id from delta.repository where name=repository_name;
$$ stable language sql;


--
-- repository_create()
--

create or replace function repository_create( repository_name text ) returns uuid as $$
declare
    _repository_id uuid;
--     _stage_commit_id uuid;
begin
    if repository_name = '' then
        raise exception 'Repository name cannot be empty string.';
    end if;

    if repository_name is null then
        raise exception 'Repository name cannot be null.';
    end if;

/*
    -- create the repo's stage_commit
    insert into delta.commit (manifest) values
    ('{
        "tracked_rows_added": [
        ],
        "stage_rows_added": [
        ],
        "commit_rows": [
        ]
    }')
    returning id into _stage_commit_id;
*/

    -- create repository
    insert into delta.repository (name) values (repository_name) returning id into _repository_id;

    /*
    -- point stage_commit at repository
    update delta.commit set repository_id=_repository_id where id=_stage_commit_id;
    */

    return _repository_id;
exception
    when unique_violation then
        raise exception 'Repository with name % already exists.', repository_name;
    when others then raise;
end
$$ language plpgsql;


--
-- repository_delete()
--

create or replace function _repository_delete( repository_id uuid ) returns void as $$
    begin
        if not delta._repository_exists(repository_id) then
            raise exception 'Repository with id % does not exist.', repository_id;
        end if;

        delete from delta.repository where id = repository_id;
    end;
$$ language plpgsql;

create or replace function repository_delete( repository_name text ) returns void as $$
    begin
        if not delta.repository_exists(repository_name) then
            raise exception 'Repository with name % does not exist.', repository_name;
        end if;

        perform delta._repository_delete(delta.repository_id(repository_name));

    end;
$$ language plpgsql;


--
-- repository_exists()
--

create or replace function repository_exists( _name text ) returns boolean as $$
    select exists (select 1 from delta.repository where name = _name);
$$ language sql;

create or replace function _repository_exists( repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.repository where id = repository_id);
$$ language sql;


--
-- repository_has_commits()
--

create or replace function _repository_has_commits( _repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.commit where repository_id = _repository_id);
$$ language sql;


--
-- repository_has_uncommitted_changes()
--

create or replace function _repository_has_uncommitted_changes( _repository_id uuid ) returns boolean as $$
    declare
        is_checked_out boolean;
    begin
        -- if it isn't checked out, it doesn't have uncommitted changes
        select (checkout_commit_id is not null) from delta.repository where id=_repository_id
        into is_checked_out;

        if is_checked_out then return false; end if;

        -- TODO: check for it
        return false;
    end;
$$ language plpgsql;


--
-- _commit_exists()
--

create function _commit_exists(commit_id uuid) returns boolean as $$
    select exists (select 1 from delta.commit where id=commit_id);
$$ language sql;


/*
--
-- commit_rows()
--


-- cache checker, divert to head_commit_row mat view if possible
TRASH:
create or replace function commit_rows(_commit_id uuid, _relation_id_filter meta.relation_id default null)
returns table(commit_id uuid, row_id meta.row_id) as $$
declare
    is_cached boolean;
begin
    select into is_cached exists (select 1 from delta.head_commit_row hcr where hcr.commit_id = _commit_id);

    raise debug 'commit_rows(%, %): is_cached: %', _commit_id, _relation_id_filter, is_cached;

    if not is_cached or false then
        return query select * from delta._commit_rows(_commit_id, _relation_id_filter);
    else
        return query select hcr.commit_id, hcr.row_id --, position
        from delta.head_commit_row hcr
        where hcr.row_id::meta.relation_id =
            case
                -- no op
                when _relation_id_filter is null then hcr.row_id::meta.relation_id
                -- filter
                else _relation_id_filter
            end
        and hcr.commit_id = _commit_id;
    end if;
end
$$ language plpgsql;
*/



/*
recursive cte, traverses commit ancestry, grabbing added rows and removing rows deleted

- get the ancestry tree of the commit being materialized, in a cte
- with ancestry, start with the root commit and move forward in time
- stop at releases!
- for each commit
    - add rows added
    - remove rows deleted

-- NOTE:
-- How the heck do I write a function that returns a record with one column whose type is meta.row_id?
-- If I do table(row_id meta.row_id) it thinks I'm passing in a type and returns all fields of row_id as separate columns.
-- If I do setof meta.row_id it does the same.
-- Adding (useless) commit_id to return type to fix

TRASH.  Now commits are not additive, the manifest holds the whole thing so no CTE.

create or replace function _commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns table(commit_id uuid, row_id meta.row_id) as $$
    with recursive ancestry as (
        select c.id as commit_id, c.parent_id, 0 as position from delta.commit c where c.id=_commit_id
        union
        select c.id as commit_id, c.parent_id, p.position + 1 from delta.commit c join ancestry p on c.id = p.parent_id
    ),
    -- every added row, with its position in the ancestry tree
    rows_added as (
        select min(a.position) as newest_position, cra.row_id
        from ancestry a
            join delta.commit_row_added cra on cra.commit_id = a.commit_id
        group by cra.row_id
    ),
    -- every row deleted, with its position in the ancestry tree
    rows_deleted as (
        select min(a.position) as newest_position, crd.row_id
        from ancestry a
            join delta.commit_row_deleted crd on crd.commit_id = a.commit_id
            group by crd.row_id
    )
    -- WIP
    select
        _commit_id,
        ra.row_id / * as added_row_id,
        ra.newest_position as added_position,
        rd.row_id as deleted_row_id,
        rd.newest_position * /
    from rows_added ra
        left join rows_deleted rd on rd.row_id = ra.row_id
    where (
        -- never deleted
        rd.row_id is null
        or
        -- deleted and re-added
        rd.newest_position >= ra.newest_position
    )

    and
        -- relation filter, if passed in
        (ra.row_id)::meta.relation_id =
            case
                when _relation_id is not null then _relation_id
                else (ra.row_id)::meta.relation_id
            end;
    return;
$$ language plpgsql;
*/


--
-- commit_rows()
--

create or replace function _commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns table(commit_id uuid, row_id meta.row_id) as $$
    select id, jsonb_object_keys(manifest)::meta.row_id
    from delta.commit
    where id = _commit_id /* and something something _relation_id optimization TODO */;
$$ language sql;


-- why is this necessary -- was here before for cache diversion
create or replace function commit_rows(_commit_id uuid, _relation_id_filter meta.relation_id default null)
returns table(commit_id uuid, row_id meta.row_id) as $$
    select * from delta._commit_rows(_commit_id, _relation_id_filter);
$$ language sql;


--
-- head_commit_rows()
--

create function _head_commit_rows( _repository_id uuid ) returns table(commit_id uuid, row_id meta.row_id) as $$
    select * from delta._commit_rows(delta._head_commit_id(_repository_id));
$$ language sql;


--
-- commit_fields()
--

-- a field and it's value hash
create type field_hash as ( field_id meta.field_id, value_hash text);

create or replace function _commit_fields(_commit_id uuid, _relation_id_filter /* TODO */ meta.relation_id default null)
returns setof field_hash as $$
    select meta.field_id(
        key::meta.row_id,
        (jsonb_each(value)).key
    ), -- field_id
    (jsonb_each_text(value)).value -- value_hash

    from jsonb_each((
        select manifest from delta.commit where id = _commit_id
    ));
$$ language sql;


--
-- head_commit_fields()
--
create function _head_commit_fields( _repository_id uuid ) returns setof field_hash as $$
    select * from delta._commit_fields(delta._head_commit_id(_repository_id));
$$ language sql;






/*
create function head_commit_rows( repository_name text default null ) returns table(commit_id uuid, row_id meta.row_id) as $$
declare
    repository_id uuid;
begin
    if repository_name is null then 
        return query select * from delta._head_commit_rows();
    else
        return query select * from delta._head_commit_rows(delta.repository_id(repository_name));
    end if;
end;
$$ language plpgsql;
*/

--
-- get_commit_manifest()
--

create function get_commit_manifest( _commit_id uuid ) returns jsonb as $$
    select manifest from delta.commit where id = _commit_id;
$$ language sql;


--
-- garbage_collect()
--

/*
create or replace function garbage_collect() returns setof text as $$
    delete from delta.blob
    using (
        select b.hash as bad_hash from delta.blob b
            left join GONE: delta.commit_field_changed cfc on cfc.value_hash = b.hash
        where  cfc.value_hash is null
    )
    where hash = bad_hash
    returning bad_hash
$$ language sql;
*/


/*
--
-- migrations
--

create table commit_migration (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    up_code text,
    down_code text, -- can we auto-generate a lot of this?
    before_checkout boolean,
    ordinal_position integer
);

--
-- dependencies
--

create table dependency (
    id uuid not null default public.uuid_generate_v7() primary key
);
*/
