cat ../pg_delta--0.1.0.sql | psql -v ON_ERROR_STOP=1 -v VERBOSITY=terse dev
# cat ../001-*.sql ../002-*.sql ../003-*.sql | psql -v ON_ERROR_STOP=1 -e -b
cat test.sql | psql -v ON_ERROR_STOP=1 -a
