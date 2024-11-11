select '------------- unit/init.sql ------------------------------------------';
set search_path=public;
\i ../periodic/data.sql

create schema unittest;
select no_plan();
