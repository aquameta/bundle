---------------------------------------------------------------------------------------
--
-- INIT
--
---------------------------------------------------------------------------------------
set search_path=public,shakespeare;

select delta.create_repository('org.opensourceshakespeare.db');
-- snapshot counts
select set_counts.create_counters();
