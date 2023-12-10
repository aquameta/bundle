------------------------------------------------------------------------------
-- DATA MODEL
------------------------------------------------------------------------------

--
-- repository
--

create table repository (
    id uuid not null default public.uuid_generate_v4() primary key,
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
    value text not null,
    unique(value)
);

create or replace function blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value is NULL then
            return NULL;
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
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id),
    parent_id uuid references commit(id), --null means first commit
    author_name text not null default '',
    author_email text not null default '',
    message text not null default ''
);
-- TODO: check constraint for only one null parent_id per repo

-- circular dependencies
alter table repository add head_commit_id uuid references commit(id) on delete set null;
alter table repository add checkout_commit_id uuid references commit(id) on delete set null;
alter table repository alter constraint repository_checkout_commit_id_fkey deferrable initially immediate;
alter table repository alter constraint repository_head_commit_id_fkey deferrable initially immediate;


--
-- commit_row
--

create table commit_row_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    row_id meta.row_id not null,
    position integer not null
);

create table commit_row_deleted (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    row_id meta.row_id not null,
    position integer not null
);


--
-- commit_field
--

create table commit_field_changed (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    new_value text
);

create table commit_field_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    value text
);

create table commit_field_deleted (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    field_id meta.field_id not null,
    value text
);




------------------------------------------------------------------------------
-- FUNCTIONS
------------------------------------------------------------------------------

--
-- create()
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
end
$$ language plpgsql;


--
-- delete()
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
-- exists()
--

create or replace function repository_exists( _name text ) returns boolean as $$
    select exists (select 1 from delta.repository where name = _name);
$$ language sql;

create or replace function _repository_exists( repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.repository where id = repository_id);
$$ language sql;


--
-- has_commits()
--

create or replace function _repository_has_commits( _repository_id uuid ) returns boolean as $$
    select exists (select 1 from delta.commit where repository_id = _repository_id);
$$ language sql;


--
-- id()
--

create or replace function repository_id( repository_name text ) returns uuid as $$
    select id from delta.repository where name= repository_name;
$$ stable language sql;


--
-- commit_rows()
--

/*
recursive cte, traverses commit ancestry tree, grabbing added rows and removing rows deleted

- get the ancestry tree of the commit being materialized, in a cte
- with ancestry, start with the root commit and move forward in time
- stop at releases!
- for each commit
    - add rows added
    - remove rows deleted
*/



create or replace function commit_rows( _commit_id uuid ) returns setof meta.row_id as $$
    select added_row_id from (
        with recursive ancestry as (
            select c.id as commit_id, c.parent_id, 0 as position from delta.commit c where c.id=_commit_id
            union
            select c.id as commit_id, c.parent_id, p.position + 1 from delta.commit c join ancestry p on c.id = p.parent_id
        )
        select min(a.position) as added_commit_position, cra.row_id as added_row_id
        from ancestry a
            left join delta.commit_row_added cra on cra.commit_id = a.commit_id
        group by cra.row_id
    ) cra
    left join delta.commit_row_deleted crd on crd.row_id = cra.added_row_id
    where crd.row_id is null or crd.position > crd.position;
$$ language sql;


--
-- commit_fields()
--

/*
create or replace function commit_fields( _commit_id uuid ) returns setof meta.field_id as $$
$$ language sql;
*/


/*
--
-- migrations
--

create table commit_migration (
    id uuid not null default public.uuid_generate_v4() primary key,
    commit_id uuid not null references commit(id),
    up_code text,
    down_code text, -- can we auto-generate a lot of this?
    before_checkout boolean,
    ordinal_position integer
);

--
--
-- DEPENDENCIES
--
--

create table dependency (
    id uuid not null default public.uuid_generate_v4() primary key
);
*/
