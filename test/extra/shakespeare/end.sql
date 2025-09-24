select '------------- shakespeare/end.sql ------------------------------------------';
select bundle.delete_repository('org.opensourceshakespeare.db');
select bundle.delete_repository('io.pgbundle.set_counts');
drop schema shakespeare cascade;
drop schema set_counts cascade;

