#!/bin/bash

# usage: ./import.sh <bundle_path> <database_name>

set -e

if [ $# -lt 2 ]; then
  echo "usage: $0 <bundle_path> <database_name>"
  exit 1
fi

BUNDLE="$1"
DB="$2"

# resolve absolute path
BUNDLE_FULLPATH=$(readlink -f "$BUNDLE")

psql --no-psqlrc -t -A -P pager=off -P null='' -c \
"select bundle.import_repository(pg_read_file('${BUNDLE_FULLPATH}'));" \
"$DB"
