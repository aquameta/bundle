cd ../
./run.sh
cd test/
# cat ../001-*.sql ../002-*.sql ../003-*.sql | psql -v ON_ERROR_STOP=1 -e -b
cat data/shakespeare.sql set-counts.sql shakespeare.sql | psql -v ON_ERROR_STOP=1 -b delta
