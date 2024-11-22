cat ../set-counts/set-counts.sql ../init.sql init.sql data.sql tests.sql end.sql ../end.sql | psql -v ON_ERROR_STOP=1 -b ditty
