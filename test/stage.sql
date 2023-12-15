-----------------------------------------------------------

-- stage one row
select isa_ok(
    (select delta.stage_row('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1),
    'uuid',
    'stage_row() returns a uuid'
);

-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.stage_row('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron'))
);
