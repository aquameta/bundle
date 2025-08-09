if [ -z "$1" ]; then
    echo "Usage: $0 <database_name>"
    exit 1
fi
DB_NAME=$1

./make.sh
dropdb --force $DB_NAME
createdb $DB_NAME

# Build and install meta directly (not as extension)
echo "Building and installing meta..."
cd ../meta && ./make.sh && cat meta--0.6.0.sql | psql $DB_NAME
cd ../bundle

# Install bundle
cat bundle--0.6.0.sql | psql -e -a -b $DB_NAME
rm bundle--0.6.0.sql
