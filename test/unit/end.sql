select '-------------- unit/end.sql ------------------------------------------';
select ditty.delete_repository('io.pgditty.unittest');

drop schema unittest cascade;
drop schema pt cascade;
