-- track

select refresh_counters();
select delta.track_relation_rows('io.aquadelta.test','pt','periodic_table');
select count_diff();
-- "tracked_rows()"=>"118", "untracked_rows()"=>"-118"



-- stage

select refresh_counters();
select delta.stage_tracked_rows('io.aquadelta.test');
select count_diff();
-- "stage_rows()"=>"118", "stage_row_added"=>"118"


-- commit
select refresh_counters();
select delta.commit('io.aquadelta.test', 'Periodic table', 'Eric', 'eric@aquameta.com');
-- "commit"=>"1", "stage_rows()"=>"-118", "tracked_rows()"=>"-118", "commit_fields()"=>"3304", "stage_row_added"=>"-118", "untracked_rows()"=>"118"
--                                                                                                                                             ^^ wrong


-- delete some rows
delete from pt.periodic_table where "AtomicNumber" > 100;
--  "untracked_rows()"=>"-18"
-- missing offstage_rows_deleted

