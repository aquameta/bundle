cat init.sql data/shakespeare.sql shakespeare.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
