\i test/data/periodic_table.sql 

select repository_create('pt');
update pt.periodic_table set "Discoverer" = 'This is a really long piece of text that is way longer than a hash, yo.' where "AtomicNumber" = 1;
select tracked_row_add('pt','pt','periodic_table','AtomicNumber', "AtomicNumber"::text) from pt.periodic_table where "AtomicNumber" < 3;
select stage_tracked_rows('pt');
select commit('pt', 'first 3 elements', 'Eric Hanson', 'eric@aquameta.com');
