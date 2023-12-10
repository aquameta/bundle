
select throws_ok(
    'select delta.repository_create('''')', 
    'Repository name must not be empty string'
);


/*
insert into delta.repository(id, name) values (:repo_id, 'com.aquameta.core.bundle.tests');


gt
select delta.repository_create('org.example.test');



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
