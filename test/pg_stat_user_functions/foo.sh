# psql -c "select f.name, uf.* from meta.function f left join pg_stat_user_functions uf on uf.funcid = f.id::oid where f.schema_name in ('delta', 'meta') order by calls;" delta

psql delta -c "select * from pg_stat_user_functions where schemaname='delta' order by calls desc"

