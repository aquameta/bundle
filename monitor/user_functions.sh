psql -c "select * from pg_stat_user_functions where schemaname not in ('set_counts') order by self_time desc" bundle
