cat init.sql data/periodic_table.sql periodic-table.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
