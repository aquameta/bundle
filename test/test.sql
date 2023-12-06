select delta.repository_create('org.example.test');


/*
select delta.track_row('org.example.test', 'does', 'not', 'exist', 'yo');
select delta.untrack_row('org.example.test', 'does', 'not', 'exist', 'yo');

select delta.stage_row('org.example.test', 'does', 'not', 'exist', 'yo');
select delta.unstage_row('org.example.test', 'does', 'not', 'exist', 'yo');

select delta.stage_row('does not exist', 'widget', 'widget', 'id', id::text) from widget.widget limit 1;
select delta.track_row('org.example.test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;
select delta.untrack_row('org.example.test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;
*/

select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'a%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
select delta.commit('org.example.test', 'first commit - a widgets', 'Eric Hanson', 'elhanson@gmail.com');


select delta.track_row('org.example.test', 'widget', 'widget', 'id', id::text) from widget.widget where name like 'b%';
select delta.stage_tracked_rows(delta._repository_id('org.example.test'));
select delta.commit('org.example.test', 'second commit - b widgets', 'Eric Hanson', 'elhanson@gmail.com');
