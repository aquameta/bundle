-----------------------------------------------------------
-- track one row
select delta.track_row('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'a%' order by name limit 1;

select throws_ok(
    $$
        select delta.track_row('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
        from shakespeare.character where name ilike 'a%' order by name limit 1;
    $$,
    format('Row with row_id %s is already tracked.', meta.row_id('shakespeare', 'character', 'id', 'Aaron'))
);
