---------------------------------------------------------------------------------------
--
-- INIT
--
---------------------------------------------------------------------------------------
select '------------- shakespeare/init.sql ------------------------------------------';
set search_path=public,shakespeare;

select bundle.create_repository('org.opensourceshakespeare.db');
-- snapshot counts
select set_counts.create_counters();
