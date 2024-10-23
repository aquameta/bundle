select '------------ commit.sql ----------------------------------------------';

-- neither of these work.

/*
do $$
declare returned_commit_id uuid;
begin
    select into returned_commit_id delta.commit('io.pgdelta.unittest', 'First commit', 'Joe User', 'joe@example.com');

    perform ok(
        exists(select 1 from delta.commit where id = returned_commit_id),
        'ok..'
    );
end;
$$ language plpgsql;


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

do $$ begin
    perform delta.tracked_row_add('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text))
    from shakespeare.character where name ilike 'b%' order by name limit 1;
end $$ language plpgsql;

do $$ begin
    perform delta.stage_row_add('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text))
    from shakespeare.character where name ilike 'b%' order by name limit 1;
end $$ language plpgsql;

do $$ begin
    perform delta.commit('io.pgdelta.unittest', 'Second commit', 'Joe User', 'joe@example.com');
end $$ language plpgsql;
