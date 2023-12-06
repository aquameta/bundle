select delta.repository_create(null);
select delta.repository_create('org.example.fail');

select delta.track_row('org.example.fail', 'does', 'not', 'exist', 'yo');
select delta.untrack_row('org.example.fail', 'does', 'not', 'exist', 'yo');

select delta.stage_row('org.example.fail', 'does', 'not', 'exist', 'yo');
select delta.unstage_row('does', 'not', 'exist', 'yo');

select delta.stage_row('FAILURE', 'widget', 'widget', 'id', id::text) from widget.widget limit 1;
select delta.track_row('org.example.fail', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js limit 1;
