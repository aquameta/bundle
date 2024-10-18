./make.sh; dropdb --force delta; createdb delta; cat pg_delta--0.1.0.sql test/set-counts.sql | psql -v ON_ERROR_STOP=1 -e -b delta
