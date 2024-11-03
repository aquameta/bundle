set track_functions = 'pl';

drop schema if exists stat_cache cascade;
create schema stat_cache;
set search_path=stat_cache;


-- cache stats
create materialized view stat_cache.user_functions as
select * from pg_stat_user_functions;

-- run tests...


-- diff stats with live
drop view if exists stat_diff;
create view stat_diff as
select
--    meta.function_id(mf.schema_name, mf.name, mf.type_sig),
    mf.schema_name, mf.name, mf.type_sig,
--     ufc.calls as cache_calls,
--     uf.calls as live_calls,
    uf.calls - ufc.calls as new_calls,
    uf.total_time::decimal - ufc.total_time::decimal as total_time,
    uf.self_time::decimal - ufc.self_time::decimal as self_time

from meta.function mf
    left join pg_stat_user_functions uf on uf.funcid =  mf.id::oid
    left join stat_cache.user_functions ufc on ufc.funcid = uf.funcid
where mf.schema_name = 'delta'
order by new_calls;

