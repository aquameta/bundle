-----------------------------------------------------------

/*
-- stage one row
select isa_ok(
    (select delta.staged_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1),
    'uuid'
);
*/

-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.staged_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);

-----------------------------------------------------------
/*
-- stage again
select isa_ok(
    $$ select delta.staged_row_remove('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    'uuid'
);
*/
