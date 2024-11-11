select '----------- checkout.sql ---------------------------------------------';

-- checkout
do $$
declare returned_commit_id uuid;
begin
    delete from pt.periodic_table;
    perform delta._checkout(delta.head_commit_id('io.pgdelta.unittest'));
    perform ok(
        exists(select 1 from delta.commit where id = returned_commit_id),
        'Commit() creates a commit row and returns its id'
    );
end;
$$ language plpgsql;


/*
prepare returned_commit_id as select delta.commit('io.pgdelta.unittest', 'First commit', 'Joe User', 'joe@example.com');
prepare selected_commit_id as select id from delta.commit where id = returned_commit_id;

select results_eq(
    'returned_commit_id',
    'selected_commit_id',
    'commit() creates a commit and returns it''s id'
);
*/

/*
not anymore
select isa_ok(
    (select delta.commit('io.pgdelta.unittest', 'First commit', 'Joe User', 'joe@example.com')),
    'uuid',
    'stage_row() returns a uuid'
);
*/

/*
do $$ begin
    perform delta.track_untracked_row('io.pgdelta.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform delta.stage_tracked_row('io.pgdelta.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text))
    from pt.periodic_table where "Element" ilike 'b%' order by "Element" limit 1;
end $$ language plpgsql;

do $$ begin
    perform delta.commit('io.pgdelta.unittest', 'Second commit', 'Joe User', 'joe@example.com');
end $$ language plpgsql;
*/
