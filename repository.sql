------------------------------------------------------------------------------
-- DATA MODEL
------------------------------------------------------------------------------

--
-- repository
--

create table repository (
    id uuid not null default public.uuid_generate_v7() primary key,
    name text not null check(name != ''),
    -- head_commit_id uuid, -- (circular, added later)
    -- checkout_commit_id uuid, -- (circular, added later)
    unique(name)
);


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

        NEW.hash = public.digest(NEW.value, 'sha256');
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
    repository_id uuid not null references repository(id),
    parent_id uuid references commit(id), --null means first commit
    author_name text not null default '',
    author_email text not null default '',
    message text not null default ''
);
-- TODO: check constraint for only one null parent_id per repo
-- TODO: i am not my own grandpa

--
-- add circular dependencies
--

alter table repository add head_commit_id uuid references commit(id) on delete set null;
alter table repository add checkout_commit_id uuid references commit(id) on delete set null;
-- deferred, so circular data can be loaded within a transaction
alter table repository alter constraint repository_checkout_commit_id_fkey deferrable initially
deferred;
alter table repository alter constraint repository_head_commit_id_fkey deferrable initially deferred;
alter table repository add constraint repository_head_commit_id_unique unique(head_commit_id);
alter table repository add constraint repository_checkout_commit_id_unique unique(checkout_commit_id);


--
-- commit_row
--

create table commit_row_added (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    row_id meta.row_id not null,
    position integer not null,
    unique(commit_id,row_id)
);

create table commit_row_deleted (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    row_id meta.row_id not null,
    position integer not null,
    unique(commit_id,row_id)
);


--
-- commit_field
--

create table commit_field_changed (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    value_hash text
);

create table commit_field_added (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    value_hash text
);

create table commit_field_deleted (
    id uuid not null default public.uuid_generate_v7() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    value_hash text
);



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
-- head_commit_id()
--

create or replace function _head_commit_id( repository_id uuid ) returns uuid as $$
    select head_commit_id from delta.repository where id=repository_id;
$$ stable language sql;

create or replace function head_commit_id( repository_name text ) returns uuid as $$
    select head_commit_id from delta.repository where name=repository_name;
$$ stable language sql;


--
-- _checkout_commit_id()
--

create or replace function _checkout_commit_id( repository_name text ) returns uuid as $$
    select head_commit_id from delta.repository where name=repository_name;
$$ stable language sql;


--
-- repository_create()
--

create or replace function repository_create( repository_name text ) returns uuid as $$
declare
    repository_id uuid;
begin
    if repository_name = '' then
        raise exception 'Repository name cannot be empty string.';
    end if;

    if repository_name is null then
        raise exception 'Repository name cannot be null.';
    end if;

    insert into delta.repository (name) values (repository_name) returning id into repository_id;
    return repository_id;
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

        delete from delta.repository where name = repository_name;
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
        changes_count integer;
        is_checked_out boolean;
    begin
        -- if it isn't checked out, it doesn't have uncommitted hanges
        select (checkout_commit_id is not null) from delta.repository where id=_repository_id
        into is_checked_out;

        if is_checked_out then return false; end if;

        -- TODO: check for it
        return false;
    end;
$$ language plpgsql;


--
-- commit_rows()
--

/*
recursive cte, traverses commit ancestry, grabbing added rows and removing rows deleted

- get the ancestry tree of the commit being materialized, in a cte
- with ancestry, start with the root commit and move forward in time
- stop at releases!
- for each commit
    - add rows added
    - remove rows deleted
*/

-- NOTE:
-- How the heck do I write a function that returns a record with one column whose type is meta.row_id?
-- If I do table(row_id meta.row_id) it thinks I'm passing in a type and returns all fields of row_id as separate columns.
-- If I do setof meta.row_id it does the same.
-- Adding (useless) commit_id to return type to fix
create or replace function commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns table(commit_id uuid, row_id meta.row_id) as $$
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
        ra.row_id /* as added_row_id,
        ra.newest_position as added_position,
        rd.row_id as deleted_row_id,
        rd.newest_position */
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
$$ language sql;


--
-- commit_fields()
--

-- a field and it's value hash
create type field_hash as ( field_id meta.field_id, value_hash text);

create or replace function commit_fields(_commit_id uuid) returns setof field_hash as $$
    with recursive ancestry as (
        select c.id as commit_id, c.parent_id, 0 as position from delta.commit c where c.id=_commit_id
        union
        select c.id as commit_id, c.parent_id, p.position + 1 from delta.commit c join ancestry p on c.id = p.parent_id
    ),
    fields_added as (
        select a.commit_id, a.position, cfa.field_id, cfa.value_hash
        from ancestry a
            join delta.commit_field_added cfa on cfa.commit_id = a.commit_id
    ),
    fields_deleted as (
        select a.commit_id, a.position, cfd.field_id, cfd.value_hash
        from ancestry a
            join delta.commit_field_deleted cfd on cfd.commit_id = a.commit_id
    ),
    fields_changed as (
        select a.commit_id, a.position, cfc.field_id, cfc.value_hash
        from ancestry a
            join delta.commit_field_changed cfc on cfc.commit_id = a.commit_id
    )
    --WIP
    select fa.field_id, fa.value_hash from fields_added fa left join fields_deleted fd on fa.commit_id = fd.commit_id; -- join fields_changed fc on fc.commit_id = fd.commit_id
$$ language sql;


--
-- head_commit_row
--

-- NOTE: split these up into separate views per-repository, somehow?


create materialized view head_commit_row as
select r.id as repository_id, row_id
from delta.repository r, delta.commit_rows(r.head_commit_id) row_id;

create index head_commit_row_pkey on head_commit_row(row_id);
create unique index head_commit_row_row_id_unique on head_commit_row(row_id);

--
-- head_commit_field
--

create materialized view head_commit_field as
select r.id as repository_id, cf.field_id, cf.value_hash
from delta.repository r, delta.commit_fields(r.head_commit_id) cf;

create index head_commit_field_pkey on head_commit_field(field_id);
create unique index head_commit_field_field_id_unique on head_commit_field(field_id);


--
-- garbage_collect()
--

create or replace function garbage_collect() returns void as $$
    with hashes as (
        select distinct cfa.value_hash from delta.commit_field_added cfa
        union
        select distinct cfd.value_hash from delta.commit_field_deleted cfd
    )
    delete from delta.blob b
    where b.hash not in (select distinct value_hash from hashes)
$$ language sql;


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
