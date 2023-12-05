begin;

select delta.repo_create('delta_test');
select delta.track_row('delta_test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;
select delta.untrack_row('delta_test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;


rollback;
