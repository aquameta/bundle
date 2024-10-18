cat data/shakespeare.sql shakespeare.sql | psql -v ON_ERROR_STOP=1 -b delta
