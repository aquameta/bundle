select '---------- repository.sql --------------------------------------------';

set search_path=public;

--
-- blob table and hashing
--

insert into ditty.blob(value) values('hi mom');
select results_eq(
    $$ select hash from ditty.blob where value='hi mom' $$,
    $$ select ditty.hash('hi mom')::text; $$,
    'Blob hash of val < 32 chars equals ditty.hash() output.'
);

insert into ditty.blob(value) values('this is a very long string that is longer than 32 chars');
select results_eq(
    $$ select hash from ditty.blob where value='this is a very long string that is longer than 32 chars' $$,
    $$ select ditty.hash('this is a very long string that is longer than 32 chars')::text; $$,
    'Blob hash > 32 chars equals hash() output.'
);

select results_eq(
    $$ select 'testing'; $$,
    $$ select ditty.unhash(ditty.hash('testing')); $$,
    'Unhash of hashed output equals input value'
);

/*
select results_eq(
    $$ select 'abcdefghijklmnopqrstuvwxyz1234567890'; $$,
    $$ select ditty.unhash(ditty.hash('abcdefghijklmnopqrstuvwxyz1234567890')); $$,
    'Unhash of hashed output equals input value'
);
*/

select is(
    null,
    ditty.unhash(ditty.hash(null)),
    'Unhash of hash of null is null'
);

--
-- create_repository()
--


select throws_ok(
    'select ditty.create_repository('''')',
    'Repository name cannot be empty string.'
);

select throws_ok(
    'select ditty.create_repository(null)',
    'Repository name cannot be null.'
);

prepare returned_repo_id as select ditty.create_repository('io.pgditty.unittest');
prepare selected_repo_id as select id from ditty.repository where name='io.pgditty.unittest';
select results_eq(
    'returned_repo_id',
    'selected_repo_id',
    'create_repository() creates a repository and returns it''s id'
);

--
-- repository_id()
--

prepare dereferenced_repo_id as select ditty.repository_id('io.pgditty.unittest');
select results_eq(
    'selected_repo_id',
    'dereferenced_repo_id',
    'repository_id() returns the id of the named repository'
);



--
-- repository_exists()
--

select ok(
    ditty.repository_exists('io.pgditty.unittest'),
    'repository_exists() finds an existing repository'
);

select ok(
    not ditty.repository_exists('org.example.parrot'),
    'repository_exists() does not find a non-existent repository'
);


--
-- delete_repository()
--

select throws_ok(
    'select ditty.delete_repository(''org.example.parrot'')',
    'Repository with name org.example.parrot does not exist.',
    'delete_repository() fails when deleting non-existent repository'
);

do $$ begin
    perform ditty.create_repository('org.example.banana');
    perform ditty.delete_repository('org.example.banana');
end $$ language plpgsql;

select ok(
    not exists (select id from ditty.repository where name='org.example.banana'),
    'delete_repository() deletes the repository.'
);
