cat ../init.sql ../set-counts/set-counts.sql data.sql tests.sql ../end.sql | psql -v ON_ERROR_STOP=1 -b delta
