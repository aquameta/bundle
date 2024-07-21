-- neither of these work.

/*
do $$
declare returned_commit_id uuid;
begin
    select into returned_commit_id delta.commit('org.opensourceshakespeare.db', 'First commit', 'Joe User', 'joe@example.com');

    perform ok(
        exists(select 1 from delta.commit where id = returned_commit_id),
        'ok..'
    );
end;
$$ language plpgsql;


prepare returned_commit_id as select delta.commit('org.opensourceshakespeare.db', 'First commit', 'Joe User', 'joe@example.com');
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
    (select delta.commit('org.opensourceshakespeare.db', 'First commit', 'Joe User', 'joe@example.com')),
    'uuid',
    'stage_row() returns a uuid'
);
*/

select delta.tracked_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'b%' order by name limit 1;

select delta.stage_row_add('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'b%' order by name limit 1;

select delta.commit('org.opensourceshakespeare.db', 'Second commit', 'Joe User', 'joe@example.com');
