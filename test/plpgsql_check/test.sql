-- find function warnings/errors
select
    f.*
from
    meta.function mf
cross join lateral
    checker.plpgsql_check_function_tb(
		mf.schema_name || '.' || mf.name
            || '(' || array_to_string(mf.type_sig, ',') || ')'
    ) as f
where
    mf.schema_name = 'delta'
    and mf.language = 'plpgsql'
    and mf.return_type <> 'trigger'; -- triggers don't work?


-- find dependencies
select
    mf.name, mf.type_sig, f.type as dep_type, f.oid as dep_oid, f.schema as dep_schema, f.name as dep_name, f.params as dep_params
from
    meta.function mf
cross join lateral
    checker.plpgsql_show_dependency_tb(
        mf.schema_name || '.' || mf.name
            || '(' || array_to_string(mf.type_sig, ',') || ')'
    ) as f
where
    mf.schema_name = 'delta'
        and mf.language = 'plpgsql'
        and mf.return_type <> 'trigger'
order by mf.name, f.type;

