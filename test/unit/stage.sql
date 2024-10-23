/*
 *
 * stage tests
 *
 * Assumes that an empty repository `io.pgdelta.unittest` has been created, and
 * that the periodic table dataset has been loaded.
 */


--
-- stage_row_add()
--

/*
-- fails because row not tracked

select delta.stage_row_add('io.pgdelta.unittest', 'shakespeare', 'character', 'id', id::text)
    from shakespeare.character where name ilike 'a%' order by name limit 1;
*/

-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.stage_row_add('io.pgdelta.unittest', 'shakespeare', 'character', 'id', id::text) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);
