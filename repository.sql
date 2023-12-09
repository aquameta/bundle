------------------------------------------------------------------------------
-- DATA MODEL
------------------------------------------------------------------------------

--
-- repository
--

create table repository (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    -- head_commit_id uuid, -- (circular, added later)
    -- checkout_commit_id uuid, -- (circular, added later)
    unique(name)
);

--
-- blob
--

create table blob (
    hash text unique,
    value text
);

create or replace function blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value is NULL then
            return NULL;
        end if;

        NEW.hash = public.digest(NEW.value, 'sha256');
        if exists (select 1 from blob b where b.hash = NEW.hash) then
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
    insert into delta.repository (name) values (repository_name) returning id;
$$ language sql;


--
-- delete()
--

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

create or replace function _repository_id( name text ) returns uuid as $$
    select id from delta.repository where name= _repository_id.name;
$$ stable language sql;



--
--
-- IGNORED
--
--

-- schema
create table ignored_schema (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_id meta.schema_id not null
);

-- relation
create table ignored_table (
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null
);

-- row
create table ignored_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    row_id meta.row_id
);

-- column
create table ignored_column (
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta.column_id not null
);

-- ignore self
/*
do $$
    for r in select * from meta.table where schema_name = 'delta' -- FIXME
    loop
        -- ignore all internal tables, except for ignore rules, which are version-controlled.
        if r.name not like 'ignored_%' then
            insert into ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
        end if;

        -- attach write-blocking triggers
        -- alternately, could we do this with permissions??  whoa.

    end loop;
end;
$$ language plpgsql;
*/


--
--
-- TRACKED
--
--

create table tracked_row_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    repository_id uuid not null references repository(id) on delete cascade,
    row_id meta.row_id,
    unique (row_id)
);


--
--
-- STAGE
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
--
-- MIGRATIONS
--
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
