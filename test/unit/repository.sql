DO $$ BEGIN RAISE NOTICE '----------- repository.sql ------------'; END $$;

set search_path=public;

--
-- blob table and hashing
--

insert into delta.blob(value) values('hi mom');
select results_eq(
    $$ select hash from delta.blob where value='hi mom' $$,
    $$ select delta.hash('hi mom')::text; $$,
    'Blob hash of val < 32 chars equals delta.hash() output.'
);

insert into delta.blob(value) values('this is a very long string that is longer than 32 chars');
select results_eq(
    $$ select hash from delta.blob where value='this is a very long string that is longer than 32 chars' $$,
    $$ select delta.hash('this is a very long string that is longer than 32 chars')::text; $$,
    'Blob hash > 32 chars equals hash() output.'
);

select results_eq(
    $$ select 'testing'; $$,
    $$ select delta.unhash(delta.hash('testing')); $$,
    'Unhash of hashed output equals input value'
);

/*
select results_eq(
    $$ select 'abcdefghijklmnopqrstuvwxyz1234567890'; $$,
    $$ select delta.unhash(delta.hash('abcdefghijklmnopqrstuvwxyz1234567890')); $$,
    'Unhash of hashed output equals input value'
);
*/

select is(
    null,
    delta.unhash(delta.hash(null)),
    'Unhash of hash of null is null'
);

--
-- create_repository()
--


select throws_ok(
    'select delta.create_repository('''')',
    'Repository name cannot be empty string.'
);

select throws_ok(
    'select delta.create_repository(null)',
    'Repository name cannot be null.'
);

prepare returned_repo_id as select delta.create_repository('io.pgdelta.unittest');
prepare selected_repo_id as select id from delta.repository where name='io.pgdelta.unittest';
select results_eq(
    'returned_repo_id',
    'selected_repo_id',
    'create_repository() creates a repository and returns it''s id'
);

-- create repo to later be deleted
prepare returned_repo_id2 as select delta.create_repository('org.example.banana');
prepare selected_repo_id2 as select id from delta.repository where name='org.example.banana';
select results_eq(
    'returned_repo_id2',
    'selected_repo_id2',
    'create_repository() creates a repository and returns it''s id'
);


--
-- repository_id()
--

prepare dereferenced_repo_id as select delta.repository_id('io.pgdelta.unittest');
select results_eq(
    'selected_repo_id',
    'dereferenced_repo_id',
    'repository_id() returns the id of the named repository'
);



--
-- repository_exists()
--

select ok(
    delta.repository_exists('io.pgdelta.unittest'),
    'repository_exists() finds an existing repository'
);

select ok(
    not delta.repository_exists('org.example.parrot'),
    'repository_exists() does not find a non-existent repository'
);


--
-- delete_repository()
--

select throws_ok(
    'select delta.delete_repository(''org.example.parrot'')',
    'Repository with name org.example.parrot does not exist.',
    'delete_repository() fails when deleting non-existent repository'
);

select delta.delete_repository('org.example.banana');
select ok(
    not exists (select id from delta.repository where name='org.example.banana'),
    'delete_repository() deletes the repository.'
);


/*
List of functions in repository.sql as of 10/22/2024:

_blob_hash_gen_trigger() returns trigger as $$
repository_id( repository_name text ) returns uuid as $$
_repository_name( repository_id uuid ) returns text as $$
_head_commit_id( repository_id uuid ) returns uuid as $$
head_commit_id( repository_name text ) returns uuid as $$
_checkout_commit_id( repository_id uuid ) returns uuid as $$
checkout_commit_id( repository_name text ) returns uuid as $$
create_repository( repository_name text ) returns uuid as $$
_delete_repository( repository_id uuid ) returns void as $$
delete_repository( repository_name text ) returns void as $$
garbage_collect() returns setof text as $$
repository_exists( _name text ) returns boolean as $$
_repository_exists( repository_id uuid ) returns boolean as $$
_repository_has_commits( _repository_id uuid ) returns boolean as $$
_repository_has_uncommitted_changes( _repository_id uuid ) returns boolean as $$
_commit_exists(commit_id uuid) returns boolean as $$
_get_commit_rows( _commit_id uuid, _relation_id meta.relation_id default null ) returns table(commit_id uuid, row_id meta.row_id) as $$
_get_head_commit_rows( _repository_id uuid ) returns table(commit_id uuid, row_id meta.row_id) as $$
_get_commit_fields(_commit_id uuid, _relation_id_filter meta.relation_id default null)
_get_head_commit_fields( _repository_id uuid ) returns setof field_hash as $$
_get_commit_manifest( _commit_id uuid ) returns jsonb as $$
*/
