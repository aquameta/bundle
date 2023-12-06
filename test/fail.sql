select delta.repsitory_create('org.example.test');

select delta.track_row('org.example.test', 'does', 'not', 'exist', 'yo');
select delta.untrack_row('org.example.test', 'does', 'not', 'exist', 'yo');

select delta.stage_row('org.example.test', 'does', 'not', 'exist', 'yo');
select delta.unstage_row('does', 'not', 'exist', 'yo');

select delta.stage_row('does not exist', 'widget', 'widget', 'id', id::text) from widget.widget limit 1;
select delta.track_row('org.example.test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js limit 1;
