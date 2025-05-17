select '----------- trackable.sql --------------------------------------------';
/*
 * Tracking on non-table relations
 */

create view unittest.not_a_table as
select *
from (
    values
        (1, 2, 3),
        (4, 5, 6),
        (7, 8, 9)
) AS not_a_table(a, b, c);

do $$ begin
    perform bundle._track_nontable_relation(meta.relation_id('unittest','not_a_table'), array['a']);
end $$ language plpgsql;

select results_eq(
    'select 1 from bundle.trackable_relation where relation_id = meta.relation_id(''unittest'',''not_a_table'') and pk_column_names = array[''a''];',
    'select 1',
    '_track_nontable_relation() adds relation to trackable_relations'
);

do $$ begin
    perform bundle._untrack_nontable_relation(meta.relation_id('unittest','not_a_table'));
end $$ language plpgsql;

select results_ne(
    'select 1 from bundle.trackable_relation where relation_id = meta.relation_id(''unittest'',''not_a_table'') and pk_column_names = array[''a''];',
    'select 1',
    '_untrack_nontable_relation() removes relation from trackable_relations'
);

-- track it again for testing
do $$ begin
    perform bundle._track_nontable_relation(meta.relation_id('unittest','not_a_table'), array['a']);
end $$ language plpgsql;
