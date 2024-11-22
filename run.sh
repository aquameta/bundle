./make.sh
dropdb --force ditty
createdb ditty
cat ditty--0.1.0.sql | psql -v ON_ERROR_STOP=1 -e -b ditty
rm ditty--0.1.0.sql
