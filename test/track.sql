-- track one row
select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', 'Aaron');


-- track again
select throws_ok(
    $$ select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%%' order by name limit 1; $$,
    format('Row with row_id %s is already tracked.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')::text)
);


-- remove row that isn't tracked
select throws_ok(
    $$ select delta._tracked_row_remove(delta.repository_id('orgopensourceshakespeare.db'), meta.row_id('shakespeare', 'character', 'id', id::text)) from shakespeare.character where name ilike 'a%%' order by name limit 1 $$,
    format(
        'Row with row_id %s cannot be removed because it is not tracked by supplied repository.',
        meta.row_id('shakespeare','character','id','Aaron')
    )
);


/*
-- track one row
select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'a%' order by name limit 1;
*/



