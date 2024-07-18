-----------------------------------------------------------
-- track one row
select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'a%' order by name limit 1;


-- track again
select throws_ok(
    $$ select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%%' order by name limit 1; $$,
    format('Row with row_id %s is already tracked.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')::text)
);

/*
select throws_ok(
    $$ select delta.tracked_row_remove('shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%%' order by name limit 1 $$,
    format(
        'Row with row_id %s is not tracked.',
        meta.row_id('shakespeare','character','id','Aaron')
    )
);

*/
select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'a%' order by name limit 1;


