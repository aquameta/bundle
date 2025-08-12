DiTTY - Data Version Control for PostgreSQL
===========================================

This is a SQL-only extension for PostgreSQL that provides version control for data in
PostgreSQL.  The repository is stored inside the database, and actions are implemented as PostgreSQL
views and functions.

## Install

```sh
# clone repository, including submodules

git clone --recurse-submodules git@github.com:erichanson/bundle.git
cd pg_bundle

# install required extensions

cd extensions/meta && make && sudo make install && cd ../../
cd extensions/meta_triggers && make && sudo make install && cd ../../
cd extensions/pg_uuidv7 && make && sudo make install && cd ../../

# make bundle--0.6.0.sql
./make.sh
cat bundle--0.6.0.sql | psql _your_db_
```
