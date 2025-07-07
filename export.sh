#!/bin/bash

# usage: ./export-bundle.sh <repository_name> <database_name>

set -e

if [ $# -lt 2 ]; then
  echo "usage: $0 <repository_name> <database_name>"
  exit 1
fi

REPO="$1"
DB="$2"

psql --no-psqlrc -t -A -P pager=off -P null='' -c \
"select bundle._get_repository_export(repository_id('${REPO}'));" \
"$DB"
