------------------------------------------------------------------------------
-- FILESYSTEM IMPORT / EXPORT
------------------------------------------------------------------------------

--
-- get_repository_hashes()
--
-- Gets all blob hashes for the entire bundle, spanning all commit history
-- regardless of branches etc.
--

create or replace function _get_repository_hashes( _repository_id uuid )
returns table(hash text) as $$

    select distinct f.value_hash
    from bundle.commit c
        join lateral bundle._get_commit_fields(c.id) f on true
    where c.repository_id = _repository_id;

$$ language sql;


--
-- get_repository_blobs()
--
-- Gets all blob hashes and their values
--

create or replace function _get_repository_blobs( _repository_id uuid )
returns table(hash text, value text) as $$

    select b.hash, b.value
    from bundle._get_repository_hashes(_repository_id) h
        join blob b on h.hash = b.hash;

$$ language sql;

--
-- export_repository_export
--
-- generates a json text string that contains rows from:
--    - repository
--    - commit
--    - blob
-- scoped to a single repository.
--


-- TODO: validate _repository_id etc

create or replace function _get_repository_export( _repository_id uuid ) returns text as $$
select jsonb_pretty(jsonb_build_object(
    'repository', to_jsonb(r),
    'commits', (
        select jsonb_agg(to_jsonb(c))
        from bundle.commit c
        where c.repository_id = r.id
    ),
    'blobs', (
        select jsonb_agg(to_jsonb(b))
        from bundle._get_repository_blobs(r.id) b
    )
))
from bundle.repository r
where r.id = _repository_id;

$$ language sql;




create or replace function bundle.import_repository(bundle text, checkout boolean default false)
returns void as $$
declare
    bundle_jsonb jsonb := bundle::jsonb;
    repo_name text;
begin
    -- repository
    insert into bundle.repository (
        id,
        name,
        head_commit_id,
        checkout_commit_id,
        tracked_rows_added,
        stage_rows_to_add,
        stage_rows_to_remove,
        stage_fields_to_change
    )
    select * from jsonb_to_record(bundle_jsonb->'repository')
    as x(
        id uuid,
        name text,
        head_commit_id uuid,
        checkout_commit_id uuid,
        tracked_rows_added jsonb,
        stage_rows_to_add jsonb,
        stage_rows_to_remove jsonb,
        stage_fields_to_change jsonb
    )
    on conflict (id) do nothing;

    -- blob
    insert into bundle.blob (
        hash,
        value
    )
    select * from jsonb_to_recordset(bundle_jsonb->'blobs')
    as x(
        hash text,
        value text
    )
    on conflict (hash) do nothing;

    -- commit
    insert into bundle.commit (
        id,
        parent_id,
        merge_parent_id,
        jsonb_rows,
        jsonb_fields,
        author_name,
        author_email,
        message,
        commit_time,
        repository_id
    )
    select * from jsonb_to_recordset(bundle_jsonb->'commits')
    as x(
        id uuid,
        parent_id uuid,
        merge_parent_id uuid,
        jsonb_rows jsonb,
        jsonb_fields jsonb,
        author_name text,
        author_email text,
        message text,
        commit_time timestamptz,
        repository_id uuid
    )
    on conflict (id) do nothing;

    -- perform checkout if requested
    if checkout then
        -- get the repository name from the imported data
        repo_name := bundle_jsonb->'repository'->>'name';
        if repo_name is not null then
            perform bundle.checkout(repo_name);
        end if;
    end if;

end;
$$ language plpgsql;

