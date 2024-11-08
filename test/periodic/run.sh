cat ../init.sql init.sql | psql -v -b delta
cat ../set-counts/set-counts.sql data.sql tests.sql | psql -v ON_ERROR_STOP=1 -b delta
cat end.sql ../end.sql | psql -v -b delta
