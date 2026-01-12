------------------------------------------------------------------------------
-- REMOTE BUNDLE OPERATIONS
------------------------------------------------------------------------------
-- Functions for pushing/pulling bundles to/from remote databases
------------------------------------------------------------------------------

--
-- push()
-- Push a bundle (repository + commits + data) to a remote database
--

create function push(
    remote_name text,
    repository_name text
) returns jsonb as $$
declare
    repo_id uuid;
    head_id uuid;
    repo_data jsonb;
    commits_data jsonb;
    tracked_rows jsonb;
    result jsonb;
begin
    -- Get repository
    select id, head_commit_id into repo_id, head_id
    from bundle.repository
    where name = repository_name;

    if repo_id is null then
        raise exception 'Repository % not found', repository_name;
    end if;

    if head_id is null then
        raise exception 'Repository % has no commits', repository_name;
    end if;

    -- 1. Get repository metadata as JSON
    select row_to_json(r.*)::jsonb into repo_data
    from bundle.repository r
    where id = repo_id;

    -- 2. Get all commits in history (walk from HEAD to root)
    select jsonb_agg(row_to_json(c.*)::jsonb) into commits_data
    from bundle.commit c
    where c.repository_id = repo_id
    order by c.commit_time asc;

    -- 3. Get all tracked row data
    -- For each row_id in tracked_rows_added, fetch the actual row
    select jsonb_agg(
        jsonb_build_object(
            'row_id', row_id::text,
            'data', (select row_to_json(r.*) from meta.row_select(row_id::meta.row_id) r)
        )
    ) into tracked_rows
    from jsonb_array_elements_text(
        (select tracked_rows_added from bundle.repository where id = repo_id)
    ) as row_id;

    -- 4. Push to remote
    -- Insert repository if it doesn't exist
    perform remote.row_insert(
        remote_name,
        meta.make_relation_id('bundle', 'repository'),
        repo_data
    );

    -- Insert all commits
    perform remote.rows_insert(
        remote_name,
        meta.make_relation_id('bundle', 'commit'),
        commits_data
    );

    -- Insert all tracked rows
    -- TODO: This needs to insert into the actual tables, not bundle tables
    -- We need to extract schema_name and relation_name from row_id

    return jsonb_build_object(
        'status', 'success',
        'repository', repository_name,
        'remote', remote_name,
        'head_commit', head_id,
        'commits_pushed', jsonb_array_length(commits_data),
        'rows_pushed', jsonb_array_length(tracked_rows)
    );
end;
$$ language plpgsql;


--
-- pull()
-- Pull a bundle (repository + commits + data) from a remote database
--

create function pull(
    remote_name text,
    repository_name text
) returns jsonb as $$
declare
    result jsonb;
begin
    -- TODO: Fetch repository metadata from remote
    -- TODO: Fetch all commits
    -- TODO: Fetch all tracked row data
    -- TODO: Fetch dependencies
    -- TODO: Checkout the bundle

    return jsonb_build_object(
        'status', 'success',
        'repository', repository_name,
        'remote', remote_name
    );
end;
$$ language plpgsql;
