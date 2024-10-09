insert into delta.blob(value) values('hi mom');

select results_eq(
    $$ select hash from delta.blob where value='hi mom' $$,
    $$ select digest('hi mom', 'sha256')::text; $$,
    'Blob hash equals digest() output.'
);

-----------------------------------------------------------

select throws_ok(
    'select delta.repository_create('''')',
    'Repository name cannot be empty string.'
);

select throws_ok(
    'select delta.repository_create(null)',
    'Repository name cannot be null.'
);

prepare returned_repo_id as select delta.repository_create('org.example.test');
prepare selected_repo_id as select id from delta.repository where name='org.example.test';
select results_eq(
    'returned_repo_id',
    'selected_repo_id',
    'repository_create() creates a repository and returns it''s id'
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
    'select delta.repository_delete(''org.example.parrot'')',
    'Repository with name org.example.parrot does not exist.',
    'repository_delete() fails when deleting non-existent repository'
);

select delta.repository_delete('org.example.test');
select ok(
    not exists (select id from delta.repository where name='org.example.test'),
    'repository_delete() deletes the repository.'
);

-----------------------------------------------------------

select delta.repository_create('org.opensourceshakespeare.db');
select ok(
    delta.repository_exists('org.opensourceshakespeare.db'),
    'repository_exists() finds an existing repository'
);
