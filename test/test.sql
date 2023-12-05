select delta.repo_create('delta_test');


select delta.track_row('delta_test', 'does', 'not', 'exist', 'yo');

select delta.track_row('delta_test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;
select delta.untrack_row('delta_test', 'widget', 'dependency_js', 'id', id::text) from widget.dependency_js;

select delta.track_row('delta_test', 'widget', 'widget', 'id', id::text) from widget.widget;

select delta.stage_row('delta_test', (row_id).schema_name, (row_id).relation_name, (row_id).pk_column_name, (row_id).pk_value ) from delta.tracked_row_added;
select delta.unstage_row((row_id).schema_name, (row_id).relation_name, (row_id).pk_column_name, (row_id).pk_value ) from delta.stage_row_added;

-- select delta.commit('delta_test', 'first commit');
 

