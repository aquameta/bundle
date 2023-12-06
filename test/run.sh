cd ../
cat 0*.sql | psql dev
cd test/
cat test.sql | psql dev
