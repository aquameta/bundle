select '----------- checkout.sql ---------------------------------------------';

-- checkout
do $$
declare returned_commit_id uuid;
begin
    delete from pt.periodic_table;
    perform bundle._checkout(bundle.head_commit_id('io.pgbundle.unittest'));
    perform ok(
        exists(select 1 from bundle.commit where id = returned_commit_id),
        'Commit() creates a commit row and returns its id'
    );
end;
$$ language plpgsql;



-- create a table with composite types and arrays, make sure it comes out the same
/*
do $$
declare returned_commit_id uuid;
begin
    begin
        create table unittest.complex_types (
            id uuid primary key not null default public.uuid_generate_v4(),
            a meta.row_id,
            b text[]
        );
        insert into unittest.complex_types (a,b) values (meta.make_row_id('sch','rel','pk_col', 'pk_val'), '{x,y,z}'::text[]);

        perform bundle.create_repository('io.bundle.test_complex');
        perform bundle.track_untracked_rows_by_relation('io.bundle.test_complex', meta.make_relation_id('unittest','complex_types'));
        perform bundle.stage_tracked_rows('io.bundle.test_complex');
        perform bundle.commit('io.bundle.test_complex', 'complex types', 'Testing User', 'test@example.com');
        perform bundle.delete_checkout('io.bundle.test_complex');
        perform bundle.checkout('io.bundle.test_complex');

        perform results_eq (
            $_$ select a, b from unittest.complex_types; $_$,
            $_$ select meta.make_row_id('sch','rel','pk_col', 'pk_val'), '{x,y,z}'::text[]; $_$,
            'Checkout of complex types equals committed values.'
        );

    exception
        when others then
            raise notice 'checkout exploded: %', sqlerrm;
            perform fail('Checkout of complex types equals committed values.');
    end;
end;
$$ language plpgsql;
*/






/*
prepare returned_commit_id as select bundle.commit('io.pgbundle.unittest', 'First commit', 'Joe User', 'joe@example.com');
prepare selected_commit_id as select id from bundle.commit where id = returned_commit_id;

select results_eq(
    'returned_commit_id',
    'selected_commit_id',
    'commit() creates a commit and returns it''s id'
);
*/

/*
not anymore
select isa_ok(
    (select bundle.commit('io.pgbundle.unittest', 'First commit', 'Joe User', 'joe@example.com')),
    'uuid',
    'stage_row() returns a uuid'
);
*/

/*
do $$ begin
    perform bundle.track_untracked_row('io.pgbundle.unittest', meta.make_row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform bundle.stage_tracked_row('io.pgbundle.unittest', meta.make_row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform bundle.commit('io.pgbundle.unittest', 'Second commit', 'Joe User', 'joe@example.com');
end $$ language plpgsql;
*/
