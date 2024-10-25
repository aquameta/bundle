set search_path=public,set_counts;
-- track

select refresh_counters();
select delta.track_untracked_rows_by_relation('io.pgdelta.set_counts',meta.relation_id('pt','periodic_table'));
select count_diff();



-- stage

select refresh_counters();
select delta.stage_tracked_rows('io.pgdelta.set_counts');
select count_diff();


-- commit
select refresh_counters();
select delta.commit('io.pgdelta.set_counts', 'Periodic table', 'Eric', 'eric@aquameta.com');
select count_diff();


-- delete some rows
select refresh_counters();
delete from pt.periodic_table where "AtomicNumber" > 10;
select count_diff();
-- missing offstage_deleted_rows
