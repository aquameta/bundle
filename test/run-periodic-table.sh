cat data/periodic_table.sql set-counts.sql periodic-table.sql | psql -v ON_ERROR_STOP=1 -b delta
