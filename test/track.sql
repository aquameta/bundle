-----------------------------------------------------------

select delta.repository_create('org.example.test');

select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'a%';

select delta.track_row('widget','widget','id',id) from widget.widget where name like 'f%';

select throws_ok(
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
    'repository_exists() does not find a non-existant repository'
);

-----------------------------------------------------------
select throws_ok(
    'select delta.repository_delete(''org.example.parrot'')',
    'Repository with name org.example.parrot does not exist.',
    'repository_delete() fails when deleting non-existant repository'
);

select delta.repository_delete('org.example.test');
select ok(
    not exists (select id from delta.repository where name='org.example.test'),
    'repository_delete() deletes the repository.'
);


/*
select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'a%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
select delta.commit('org.example.test', 'first commit - a widgets', 'Eric Hanson', 'elhanson@gmail.com');
select delta.commit_row((select head_commit_id from delta.repository where name='org.example.test'));



select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'b%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
select delta.delete_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'a%' limit 1;
select delta.commit('org.example.test', 'second commit - b widgets, delete one a widget', 'Eric Hanson', 'elhanson@gmail.com');
select delta.commit_row((select head_commit_id from delta.repository where name='org.example.test'));

select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'c%';
select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'd%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
select delta.delete_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'b%';
select delta.commit('org.example.test', 'third commit - c and d widgets, delete b widgets', 'Eric Hanson', 'elhanson@gmail.com');
select delta.commit_row((select head_commit_id from delta.repository where name='org.example.test'));

select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'e%';
select delta.delete_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'c%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
-- select delta.commit('org.example.test', 'fourth commit - e widgets, delete c widgets', 'Eric Hanson', 'elhanson@gmail.com');
*/
