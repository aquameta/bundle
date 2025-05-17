./make.sh
dropdb --force bundle
createdb bundle
cat bundle--0.1.0.sql | psql -v ON_ERROR_STOP=1 -e -b bundle
rm bundle--0.1.0.sql
