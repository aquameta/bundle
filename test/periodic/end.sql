select '------------- periodic/end.sql ------------------------------------------';
select ditty.delete_repository('io.pgditty.pt');
select ditty.delete_repository('io.pgditty.set_counts');
drop schema if exists pt cascade;
drop schema if exists unittest cascade;
drop schema if exists set_counts cascade;
