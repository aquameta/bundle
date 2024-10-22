insert into delta.blob(value) values('hi mom');

select results_eq(
    $$ select hash from delta.blob where value='hi mom' $$,
    $$ select digest('hi mom', 'sha256')::text; $$,
    'Blob hash equals digest() output.'
);

-----------------------------------------------------------

select throws_ok(
    'select delta.create_repository('''')',
    'Repository name cannot be empty string.'
);

select throws_ok(
    'select delta.create_repository(null)',
    'Repository name cannot be null.'
);

prepare returned_repo_id as select delta.create_repository('org.example.test');
prepare selected_repo_id as select id from delta.repository where name='org.example.test';
select results_eq(
    'returned_repo_id',
    'selected_repo_id',
    'create_repository() creates a repository and returns it''s id'
);

-----------------------------------------------------------

prepare dereferenced_repo_id as select delta.repository_id('org.example.test');
select results_eq(
    'selected_repo_id',
    'dereferenced_repo_id',
    'repository_id() returns the id of the named repository'
);


-----------------------------------------------------------

select ok(
    delta.repository_exists('org.example.test'),
    'repository_exists() finds an existing repository'
);

select ok(
    not delta.repository_exists('org.example.banana'),
    'repository_exists() does not find a non-existent repository'
);

-----------------------------------------------------------
select throws_ok(
    'select delta.delete_repository(''org.example.parrot'')',
    'Repository with name org.example.parrot does not exist.',
    'delete_repository() fails when deleting non-existent repository'
);

select delta.delete_repository('org.example.test');
select ok(
    not exists (select id from delta.repository where name='org.example.test'),
    'delete_repository() deletes the repository.'
);

-----------------------------------------------------------

select delta.create_repository('org.opensourceshakespeare.db');
select ok(
    delta.repository_exists('org.opensourceshakespeare.db'),
    'repository_exists() finds an existing repository'
);
