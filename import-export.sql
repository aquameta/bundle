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
returns table(hash text, blob text) as $$

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
