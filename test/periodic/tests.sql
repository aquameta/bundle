set search_path=public,pt,set_counts;
select no_plan();
-- track

select refresh_counters();
select ditty.track_untracked_rows_by_relation('io.pgditty.pt',meta.relation_id('pt','periodic_table'));
select count_diff();



-- stage

select refresh_counters();
select ditty.stage_tracked_rows('io.pgditty.pt');
select count_diff();


-- commit
select refresh_counters();
select ditty.commit('io.pgditty.pt', 'Periodic table', 'Eric', 'eric@aquameta.com');
select count_diff();


-- delete some rows
select refresh_counters();
delete from pt.periodic_table where "AtomicNumber" > 10;
select count_diff();
-- missing offstage_deleted_rows


select ok(true);
select finish();
