select '------------- unit/init.sql ------------------------------------------';
\i ../periodic/data.sql

create schema unittest;

select no_plan();
