select '-------------- unit/end.sql ------------------------------------------';
select finish();


select delta.delete_repository('io.pgdelta.unittest');

drop schema shakespeare cascade;
drop schema unittest cascade;
drop schema pt cascade;
