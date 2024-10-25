---------------------------------------------------------------------------------------
--
-- INIT
--
---------------------------------------------------------------------------------------
set search_path=public,set_counts;
-- snapshot counts
select set_counts.create_counters();


---------------------------------------------------------------------------------------
--
-- TESTS
--
---------------------------------------------------------------------------------------

---------------------------------------
-- empty bundle
---------------------------------------
select row_eq(
    $$ select set_counts.count_diff() $$,
    row (''::hstore),
    'No difference'
);

---------------------------------------
-- new untracked rows
---------------------------------------
insert into shakespeare.character (id, name, speech_count) values ('9001', 'Zonker', 0);
insert into shakespeare.character (id, name, speech_count) values ('9002', 'Pluto', 0);

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('_get_untracked_rows()=>2'::hstore),
    'New rows'
);

---------------------------------------
-- track rows
---------------------------------------
select delta.tracked_row_add('io.pgdelta.set_counts',meta.row_id('shakespeare','character','id',id)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('_get_tracked_rows()=>2,tracked_row_added=>2'::hstore),
    'New tracked rows'
);


---------------------------------------
-- stage_tracked_row()
---------------------------------------
select delta.stage_tracked_row('io.pgdelta.set_counts',meta.row_id('shakespeare','character','id',id::text)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('_get_stage_tracked_rows=>2,_get_tracked_rows()=>2,_get_stage_rows()=>2'::hstore),
    'Stage tracked rows'
);

-------------------------------------------------------------------------------
-- commit()
-------------------------------------------------------------------------------
select delta.commit('io.pgdelta.set_counts','First commit!','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,get_commit_rows()=>2,_get_tracked_rows()=>2,commit_fields()=>10,get_db_commit_fields=>10,db_commit_rows=>2,get_db_head_commit_rows()=>2'::hstore),
    'Commit makes a commit and adds the staged rows'
);

-------------------------------------------------------------------------------
-- refresh_counters()
-------------------------------------------------------------------------------
select set_counts.refresh_counters();

select row_eq(
    $$ select set_counts.count_diff() $$,
    row (''::hstore),
    'refresh_counters() refreshes counters'
);

---------------------------------------
-- delete a row in a commit
---------------------------------------
delete from shakespeare.character where id='9001';

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('offstage_row_deleted()=>1'::hstore),
    'Delete a row in a commit'
);


---------------------------------------
-- stage the delete
---------------------------------------
select delta.stage_row_to_remove('io.pgdelta.set_counts',meta.row_id('shakespeare','character','id','9001'));

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_row_to_removes=>1,_get_stage_rows()=>-1'::hstore),
    'Stage a row delete'
);

---------------------------------------
-- commit
---------------------------------------
select delta.commit('io.pgdelta.set_counts','Second commit, delete one row','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Commit a row delete'
);

---------------------------------------
-- track all of shakespeare
---------------------------------------
select set_counts.refresh_counters();
select delta.track_relation_rows('io.pgdelta.set_counts', meta.relation_id(schema_name, name)) from meta.table where schema_name='shakespeare';

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Track shakespeare'
);

---------------------------------------
-- stage_tracked_rows
---------------------------------------
select delta.stage_tracked_rows('io.pgdelta.set_counts');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Stage shakespeare'
);

---------------------------------------
-- commit
---------------------------------------
select delta.commit('io.pgdelta.set_counts','Third commit, add all of shakespeare','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Commit shakespeare'
);
