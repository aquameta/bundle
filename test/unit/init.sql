select '------------- init.sql -----------------------------------------------';
-- TODO: get this crap outta here
drop schema if exists shakespeare cascade;
\i ../shakespeare/data.sql

drop schema if exists periodic cascade;
\i ../periodic/data.sql
