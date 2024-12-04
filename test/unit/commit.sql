select '------------ commit.sql ----------------------------------------------';

-- commit
do $$
declare returned_commit_id uuid;
begin
    select into returned_commit_id ditty.commit('io.pgditty.unittest', 'First commit', 'Joe User', 'joe@example.com');

    perform ok(
        exists(select 1 from ditty.commit where id = returned_commit_id),
        'Commit() creates a commit row and returns its id'
    );
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
    from pt.periodic_table; -- where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform ditty.stage_tracked_row('io.pgditty.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table; --  where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform ditty.commit('io.pgditty.unittest', 'All of periodic table', 'Joe User', 'joe@example.com');
end $$ language plpgsql;
*/
