select delta.delete_repository('org.opensourceshakespeare.db');
select delta.delete_repository('io.pgdelta.set_counts');
drop schema shakespeare cascade;
drop schema set_counts cascade;

