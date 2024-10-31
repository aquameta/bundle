cat ../init.sql init.sql test.sql end.sql ../end.sql | psql -v ON_ERROR_STOP=1 -b delta
