cat init.sql repository.sql db.sql ignore.sql track.sql stage.sql commit.sql checkout.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
cat init.sql data/periodic_table.sql periodic-table.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
cat init.sql data/shakespeare.sql shakespeare.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
