# psql -c "select f.name, uf.* from meta.function f left join pg_stat_user_functions uf on uf.funcid = f.id::oid where f.schema_name in ('bundle', 'meta') order by calls;" bundle

psql bundle -c "select * from pg_stat_user_functions where schemaname='bundle' order by calls desc"

