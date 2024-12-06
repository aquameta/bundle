select '-------------- unit/end.sql ------------------------------------------';

drop schema if exists unittest cascade;
drop schema if exists pt cascade;
select ditty.delete_repository('io.pgditty.unittest');
