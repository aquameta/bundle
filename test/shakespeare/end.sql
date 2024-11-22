select ditty.delete_repository('org.opensourceshakespeare.db');
select ditty.delete_repository('io.pgditty.set_counts');
drop schema shakespeare cascade;
drop schema set_counts cascade;

