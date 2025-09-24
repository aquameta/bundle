cat ../../_begin.sql ../set-counts/set-counts.sql init.sql data.sql tests.sql end.sql ../../_end.sql | psql -v ON_ERROR_STOP=1 -b aquameta
