select '------------ stage.sql -----------------------------------------------';
/*
 *
 * stage tests
 *
 * Assumes that an empty repository `io.pgdelta.unittest` has been created, and
 * that the periodic table dataset has been loaded.
 */


--
-- stage_tracked_row()
--

select delta.status();

-- track and stage one row
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform delta.track_untracked_row(
            'io.pgdelta.unittest',
            row_id
        );

        perform delta.stage_tracked_row(
            'io.pgdelta.unittest',
            row_id
        );
    end;
$$ language plpgsql;


--
-- is_staged()
--

select ok(
    (select delta._is_staged(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1'))
     ),
    '_is_staged() finds staged row.'
);

select ok(
    (select not delta._is_staged(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '2'))
     ),
    '_is_staged() does not find off-stage row.'
);


--
-- _get_stage_rows_to_add()
--

select results_eq(
   $$ select row_id::text from delta._get_stage_rows_to_add(delta.repository_id('io.pgdelta.unittest')) $$,
   array['(pt,periodic_table,{AtomicNumber},{1})'],
   '_get_stage_rows_to_add() finds staged row'
);


do $$ begin
    -- commit the single row change
    perform delta.commit('io.pgdelta.unittest', 'first element', 'Test User', 'test@example.com');
    -- update pt.periodic_table set "Discoverer" = 'Don Henley' where "AtomicNumber" = 1;
end; $$ language plpgsql;

select results_eq(
   $$ select row_id::text from delta._get_stage_rows_to_add(delta.repository_id('io.pgdelta.unittest')) $$,
   array[]::text[],
   '_get_stage_rows_to_add() does not find staged row after commit.'
);

select delta.status();


--
-- stage_row_to_remove()
--

-- stage delete of commited row
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform delta.stage_row_to_remove(
            'io.pgdelta.unittest',
            row_id
        );
    end;
$$ language plpgsql;




--
-- fields
--

do $$ begin
    -- commit the single row change
    update pt.periodic_table set "Discoverer" = 'Don Henley' where "AtomicNumber" = 1;
end; $$ language plpgsql;







-- track and stage twenty rows
/*
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform delta.track_untracked_row(
            'io.pgdelta.unittest',
            meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text)
        )
        from pt.periodic_table where "AtomicNumber" = 1;

        perform delta.stage_tracked_row(
            'io.pgdelta.unittest',
            meta.row_id('pt','periodic_table','AtomicNumber', "AtomicNumber"::text)
        ) from pt.periodic_table where "AtomicNumber" = 1;

    end;
$$ language plpgsql;
*/


/*
-- fails because row not tracked

select delta.stage_tracked_row('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text))
    from shakespeare.character where name ilike 'a%' order by name limit 1;
*/
-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.stage_tracked_row('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text)) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);
