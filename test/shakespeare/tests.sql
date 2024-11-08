---------------------------------------------------------------------------------------
--
-- INIT
--
---------------------------------------------------------------------------------------
set search_path=public,shakespeare;
-- snapshot counts

-- select delta.delete_repository('org.opensourceshakespeare.db');
select delta.create_repository('org.opensourceshakespeare.db');
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
    row ('untracked_rows=>2'::hstore),
    'New rows'
);

---------------------------------------
-- track rows
---------------------------------------
select delta.track_untracked_row('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id',id)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('tracked_rows=>2,track_untracked_rowed=>2'::hstore),
    'New tracked rows'
);


---------------------------------------
-- stage_tracked_row()
---------------------------------------
select delta.stage_tracked_row('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id',id::text)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_tracked_rows=>2,tracked_rows=>2,stage_rows=>2'::hstore),
    'Stage tracked rows'
);

-------------------------------------------------------------------------------
-- commit()
-------------------------------------------------------------------------------
select delta.commit('org.opensourceshakespeare.db','First commit!','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,get_commit_rows=>2,tracked_rows=>2,commit_fields=>10,get_db_commit_fields=>10,db_commit_rows=>2,get_db_head_commit_rows=>2'::hstore),
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
    row ('offstage_deleted_rows=>1'::hstore),
    'Delete a row in a commit'
);


---------------------------------------
-- stage the delete
---------------------------------------
select delta.stage_row_to_remove('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id','9001'));

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_row_to_removes=>1,stage_rows=>-1'::hstore),
    'Stage a row delete'
);

---------------------------------------
-- commit
---------------------------------------
select delta.commit('org.opensourceshakespeare.db','Second commit, delete one row','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Commit a row delete'
);

---------------------------------------
-- track all of shakespeare
---------------------------------------
select set_counts.refresh_counters();
select delta.track_untracked_rows_by_relation('org.opensourceshakespeare.db', meta.relation_id(schema_name, name)) from meta.table where schema_name='shakespeare' and name in ('character', 'work', 'wordform', 'chapter', 'character_work');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Track shakespeare'
);

---------------------------------------
-- stage_tracked_rows
---------------------------------------
select delta.stage_tracked_rows('org.opensourceshakespeare.db');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Stage shakespeare'
);

---------------------------------------
-- commit
---------------------------------------
select delta.commit('org.opensourceshakespeare.db','Third commit, add all of shakespeare','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit=>1,commit_row_deleted=>1,untracked_row=>1'::hstore),
    'Commit shakespeare'
);
