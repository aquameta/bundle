cat ../init.sql init.sql | psql -v -b bundle
cat ../set-counts/set-counts.sql data.sql tests.sql | psql -v ON_ERROR_STOP=1 -b bundle
