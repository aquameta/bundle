select '------------ stage.sql -----------------------------------------------';
/*
 *
 * stage tests
 *
 * Assumes that an empty repository `io.pgbundle.unittest` has been created, and
 * that the periodic table dataset has been loaded.
 */


--
-- stage_tracked_row()
--

-- select bundle.status();

-- track and stage one row
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform bundle.track_untracked_row(
            'io.pgbundle.unittest',
            row_id
        );

        perform bundle.stage_tracked_row(
            'io.pgbundle.unittest',
            row_id
        );
    end;
$$ language plpgsql;


--
-- is_staged()
--

select ok(
    (select bundle._is_staged(
        bundle.repository_id('io.pgbundle.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1'))
     ),
    '_is_staged() finds staged row.'
);

select ok(
    (select not bundle._is_staged(
        bundle.repository_id('io.pgbundle.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '2'))
     ),
    '_is_staged() does not find off-stage row.'
);


--
-- _get_stage_rows_to_add()
--

select results_eq(
   $$ select row_id::text from bundle._get_stage_rows_to_add(bundle.repository_id('io.pgbundle.unittest')) $$,
   array['(pt,periodic_table,{AtomicNumber},{1})'],
   '_get_stage_rows_to_add() finds staged row'
);


do $$ begin
    -- commit the single row change
    perform bundle.commit('io.pgbundle.unittest', 'first element', 'Test User', 'test@example.com');
    -- update pt.periodic_table set "Discoverer" = 'Don Henley' where "AtomicNumber" = 1;
end; $$ language plpgsql;

select results_eq(
   $$ select row_id::text from bundle._get_stage_rows_to_add(bundle.repository_id('io.pgbundle.unittest')) $$,
   array[]::text[],
   '_get_stage_rows_to_add() does not find staged row after commit.'
);

-- select bundle.status();


--
-- stage_row_to_remove()
--

do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform bundle.stage_row_to_remove(
            'io.pgbundle.unittest',
            row_id
        );
    end;
$$ language plpgsql;

-- TODO: unstage_row_to_remove()

/*
--
-- fields
--

TODO: this should fail because you can't change a removed row (and it is removed above)
do $$ begin
    -- commit the single row change
    update pt.periodic_table set "Discoverer" = 'Don Henley' where "AtomicNumber" = 1;
end; $$ language plpgsql;




*/



-- track and stage twenty rows
/*
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform bundle.track_untracked_row(
            'io.pgbundle.unittest',
            meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text)
        )
        from pt.periodic_table where "AtomicNumber" = 1;

        perform bundle.stage_tracked_row(
            'io.pgbundle.unittest',
            meta.row_id('pt','periodic_table','AtomicNumber', "AtomicNumber"::text)
        ) from pt.periodic_table where "AtomicNumber" = 1;

    end;
$$ language plpgsql;
*/


/*
-- fails because row not tracked

select bundle.stage_tracked_row('io.pgbundle.unittest', meta.row_id('shakespeare', 'character', 'id', id::text))
    from shakespeare.character where name ilike 'a%' order by name limit 1;
*/
-----------------------------------------------------------
/*
-- stage again
select throws_ok(
    $$ select bundle.stage_tracked_row('io.pgbundle.unittest', meta.row_id('shakespeare', 'character', 'id', id::text)) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);
*/
