-----------------------------------------------------------

-- stage one row
select delta.stage_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
    from shakespeare.character where name ilike 'a%' order by name limit 1;

-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.stage_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);
