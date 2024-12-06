select '----------- checkout.sql ---------------------------------------------';

-- checkout
do $$
declare returned_commit_id uuid;
begin
    delete from pt.periodic_table;
    perform ditty._checkout(ditty.head_commit_id('io.pgditty.unittest'));
    perform ok(
        exists(select 1 from ditty.commit where id = returned_commit_id),
        'Commit() creates a commit row and returns its id'
    );
end;
$$ language plpgsql;



-- create a table with composite types and arrays, make sure it comes out the same
do $$
declare returned_commit_id uuid;
begin
    begin
        create table unittest.complex_types (
            id uuid primary key not null default public.uuid_generate_v7(),
            a meta.row_id,
            b text[]
        );
        insert into unittest.complex_types (a,b) values (meta.row_id('sch','rel','pk_col', 'pk_val'), '{x,y,z}'::text[]);

        perform ditty.create_repository('io.ditty.test_complex');
        perform ditty.track_untracked_rows_by_relation('io.ditty.test_complex', meta.relation_id('unittest','complex_types'));
        perform ditty.stage_tracked_rows('io.ditty.test_complex');
        perform ditty.commit('io.ditty.test_complex', 'complex types', 'Testing User', 'test@example.com');
        perform ditty.delete_checkout('io.ditty.test_complex');
        perform ditty.checkout('io.ditty.test_complex');

        perform results_eq (
            $_$ select * from unittest.test_complex; $_$,
            $_$ select row(meta.field_id('sch','rel','pk_col', 'pk_val'), '{x,y,z}'::text[]); $_$,
            'Checkout of complex types equals committed values.'
        );

        drop table unittest.complex_types;
        perform ditty.delete_repository('io.ditty.test_complex');

    exception
        when others then
            raise notice 'checkout exploded: %', sqlerrm;
            perform fail('Checkout of complex types equals committed values.');
    end;
end;
$$ language plpgsql;






/*
prepare returned_commit_id as select ditty.commit('io.pgditty.unittest', 'First commit', 'Joe User', 'joe@example.com');
prepare selected_commit_id as select id from ditty.commit where id = returned_commit_id;

select results_eq(
    'returned_commit_id',
    'selected_commit_id',
    'commit() creates a commit and returns it''s id'
);
*/

/*
not anymore
select isa_ok(
    (select ditty.commit('io.pgditty.unittest', 'First commit', 'Joe User', 'joe@example.com')),
    'uuid',
    'stage_row() returns a uuid'
);
*/

/*
do $$ begin
    perform ditty.track_untracked_row('io.pgditty.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform ditty.stage_tracked_row('io.pgditty.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform ditty.commit('io.pgditty.unittest', 'Second commit', 'Joe User', 'joe@example.com');
end $$ language plpgsql;
*/
