cat ../000-init.sql | psql -v ON_ERROR_STOP=1 -v VERBOSITY=terse dev
cat ../001-*.sql ../002-*.sql ../003-*.sql | psql -v ON_ERROR_STOP=1 -e -b
cat fail.sql | psql -e -b
