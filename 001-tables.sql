set search_path=delta;
--
--
-- REPOSITORY
--
--

create table repository (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    -- head_commit_id uuid, -- (circular, added later)
    -- checkout_commit_id uuid, -- (circular, added later)
    unique(name)
);

--
--
-- BLOB
--
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
--
-- COMMIT
--
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



create type _commit_ancestry as (commit_id uuid, position integer);
create or replace function _commit_ancestry( _commit_id uuid ) returns setof _commit_ancestry as $$
    with recursive parent as (
        select c.id, c.parent_id, 1 as position from commit c where c.id=_commit_id
        union
        select c.id, c.parent_id, p.position + 1 from commit c join parent p on c.id = p.parent_id
    ) select id, position from parent
$$ language sql;



/*
recursive cte, traverses commit ancestry tree, grabbing added rows and removing rows deleted

- get the ancestry tree of the commit being materialized, in a cte
- with ancestry, start with the root commit and move forward in time
- stop at releases!
- for each commit
    - add rows added
    - remove rows deleted
*/

create or replace function commit_row( _commit_id uuid ) returns setof meta.row_id as $$
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
