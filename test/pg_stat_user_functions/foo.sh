# psql -c "select f.name, uf.* from meta.function f left join pg_stat_user_functions uf on uf.funcid = f.id::oid where f.schema_name in ('ditty', 'meta') order by calls;" ditty

psql ditty -c "select * from pg_stat_user_functions where schemaname='ditty' order by calls desc"

