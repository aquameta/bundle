set search_path=public,pt,set_counts;
select no_plan();
-- track

select refresh_counters();
select bundle.track_untracked_rows_by_relation('io.pgbundle.pt',meta.relation_id('pt','periodic_table'));
select count_diff();



-- stage

select refresh_counters();
select bundle.stage_tracked_rows('io.pgbundle.pt');
select count_diff();


-- commit
select refresh_counters();
select bundle.commit('io.pgbundle.pt', 'Periodic table', 'Eric', 'eric@aquameta.com');
select count_diff();


-- delete some rows
select refresh_counters();
delete from pt.periodic_table where "AtomicNumber" > 10;
select count_diff();
-- missing offstage_deleted_rows


select ok(true);
select finish();
