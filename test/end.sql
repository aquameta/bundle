select '-------------- end.sql -----------------------------------------------';
drop extension pgtap;

-- commit;
select '-------------- unit/end.sql ------------------------------------------';

drop schema if exists unittest cascade;
drop schema if exists pt cascade;
select bundle.delete_repository('io.pgbundle.unittest');
-- select bundle.delete_repository('io.bundle.test_complex'); -- test is commented out
