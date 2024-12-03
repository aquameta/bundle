---------------------------------------------------------------------------------------
--
-- TESTS
--
---------------------------------------------------------------------------------------

select no_plan();
select set_counts.refresh_counters();

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
select set_counts.refresh_counters();
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
select set_counts.refresh_counters();
select ditty.track_untracked_row('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id',id)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('tracked_rows=>2,tracked_rows_added=>2,untracked_rows=>-2'::hstore),
    'New tracked rows'
);


---------------------------------------
-- stage_tracked_row()
---------------------------------------
select set_counts.refresh_counters();
select ditty.stage_tracked_row('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id',id::text)) from shakespeare.character where id in ('9001','9002');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_rows_to_add=>2,tracked_rows_added=>-2,stage_rows=>2'::hstore),
    'Stage tracked rows'
);

-------------------------------------------------------------------------------
-- commit()
-------------------------------------------------------------------------------
select set_counts.refresh_counters();
select ditty.commit('org.opensourceshakespeare.db','First commit!','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row('commit_fields=>10, commit_ancestry=>1, head_commit_rows=>2, stage_rows_to_add=>-2, head_commit_fields=>10, db_head_commit_rows=>2, db_head_commit_fields=>10, commit_row_count_by_relation=>1'::hstore),
    'Commit makes a commit and adds the staged rows'
);

---------------------------------------
-- delete a row in a commit
---------------------------------------
select set_counts.refresh_counters();
delete from shakespeare.character where id='9001';

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('offstage_deleted_rows=>1,db_head_commit_fields=>-5'::hstore),
    'Delete a row in a commit'
);


---------------------------------------
-- stage the remove 
---------------------------------------
select set_counts.refresh_counters();
select ditty.stage_row_to_remove('org.opensourceshakespeare.db',meta.row_id('shakespeare','character','id','9001'));

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_rows_to_remove=>1,stage_rows=>-1,offstage_deleted_rows=>-1'::hstore),
    'Stage a row remove'
);


---------------------------------------
-- commit
---------------------------------------
select set_counts.refresh_counters();
select ditty.commit('org.opensourceshakespeare.db','Second commit, delete one row','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('tracked_rows=>-1, commit_ancestry=>1, head_commit_rows=>-1, db_head_commit_rows=>-1, stage_rows_to_remove=>-1'::hstore),
    'Commit a row delete'
);


-- TODO: remove a row that exists

---------------------------------------
-- track all of shakespeare
---------------------------------------
select set_counts.refresh_counters();
select ditty.track_untracked_rows_by_relation('org.opensourceshakespeare.db', meta.relation_id(schema_name, name))
from meta.table
where schema_name='shakespeare'
--    and name in ('character', 'work', 'chapter', 'character_work') -- 'paragraph', 'wordform'
;

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('tracked_rows=>67895, untracked_rows=>-67895, tracked_rows_added=>67895'::hstore),
    'Track all of shakespeare'
);

---------------------------------------
-- stage_tracked_rows
---------------------------------------
select set_counts.refresh_counters();
select ditty.stage_tracked_rows('org.opensourceshakespeare.db');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_rows=>67895, stage_rows_to_add=>67895, tracked_rows_added=>-67895'::hstore),
    'Stage all of shakespeare'
);

---------------------------------------
-- commit
---------------------------------------
select set_counts.refresh_counters();
select ditty.commit('org.opensourceshakespeare.db','Third commit, add all of shakespeare','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit_fields=>583864, commit_ancestry=>1, head_commit_rows=>67895, stage_rows_to_add=>-67895, head_commit_fields=>583864, db_head_commit_rows=>67895, db_head_commit_fields=>583864, commit_row_count_by_relation=>5'::hstore),
    'Commit all of shakespeare'
);

---------------------------------------
-- update fields
---------------------------------------
select set_counts.refresh_counters();
update shakespeare.character set description = description || ditty.random_string(3);
update shakespeare.character set name = name || ditty.random_string(3);
select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('offstage_updated_fields=>1887'::hstore),
    'Update committed rows in shakespeare'
);

---------------------------------------
-- stage updated fields
---------------------------------------
select set_counts.refresh_counters();
select ditty.stage_updated_fields('org.opensourceshakespeare.db', meta.relation_id('shakespeare','character'));
select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('stage_fields_to_change=>1887, offstage_updated_fields=>-1887, db_stage_fields_to_change=>1887'::hstore),
    'Stage updated fields in shakespeare'
);

---------------------------------------
-- commit updated fields
---------------------------------------
select set_counts.refresh_counters();
select ditty.commit('org.opensourceshakespeare.db','Fourth commit, update a bunch of fields.','Testing User','testing@example.com');

select row_eq(
    $$ select set_counts.count_diff() $$,
    row ('commit_ancestry=>1, stage_fields_to_change=>-1887, db_stage_fields_to_change=>-1887'::hstore),

    'Commit shakespeare'
);

---------------------------------------
-- delete_checkout() + checkout() TODO split up
---------------------------------------

select ditty.delete_checkout('org.opensourceshakespeare.db');
select ditty.checkout('org.opensourceshakespeare.db');
select set_counts.refresh_counters();
select row_eq(
    $$ select set_counts.count_diff() $$,
    row (''::hstore),
    'Delete checkout + checkout does nothing.'
);

select finish();
