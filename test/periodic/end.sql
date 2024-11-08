select '------------- periodic/end.sql ------------------------------------------';
select delta.delete_repository('io.pgdelta.pt');
select delta.delete_repository('io.pgdelta.set_counts');
drop schema if exists pt cascade;
drop schema if exists unittest cascade;
drop schema if exists set_counts cascade;
