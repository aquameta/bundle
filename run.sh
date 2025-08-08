./make.sh
dropdb --force bundle
createdb bundle

# Build and install meta directly (not as extension)
echo "Building and installing meta..."
cd ~/dev/meta && ./make.sh && cat meta--0.6.0.sql | psql bundle
cd -

# Install bundle
# cat bundle--0.6.0.sql | psql -v ON_ERROR_STOP=1 -e -a -b bundle
cat bundle--0.6.0.sql | psql -e -a -b bundle
rm bundle--0.6.0.sql
