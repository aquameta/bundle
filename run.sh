if [ -z "$1" ]; then
    echo "Usage: $0 <database_name>"
    exit 1
fi
DB_NAME=$1
./make.sh
dropdb --force $DB_NAME
createdb $DB_NAME
cat bundle--0.6.0.sql | psql -v ON_ERROR_STOP=1 -e -b $DB_NAME
rm bundle--0.6.0.sql
