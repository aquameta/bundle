select '------------- periodic/end.sql ------------------------------------------';
select bundle.delete_repository('io.pgbundle.pt');
select bundle.delete_repository('io.pgbundle.set_counts');
drop schema if exists pt cascade;
drop schema if exists unittest cascade;
drop schema if exists set_counts cascade;
