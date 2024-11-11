select '-------------- unit/end.sql ------------------------------------------';
select delta.delete_repository('io.pgdelta.unittest');

drop schema unittest cascade;
drop schema pt cascade;
