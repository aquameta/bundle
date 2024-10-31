set track_functions = 'pl';
create schema "stat_cache";

-- cache stats
create materialized view stat_cache.pg_stat_user_functions as
select * from pg_stat_user_functions;



-- run tests...


-- diff stats with live
select
    meta.function_id(mf.schema_name, mf.name, mf.type_sig),
    cache.calls as old_calls,
    live.calls as new_calls
from pg_stat_user_functions live
    join stat_cache.pg_stat_user_functions cache
        on cache.funcid = live.funcid
    join meta.function mf
        on mf.name = live.funcname
            and mf.schema_name = live.schemaname
;




