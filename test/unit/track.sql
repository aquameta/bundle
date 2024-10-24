select '------------- track.sql --------------------------------------------------';
/*
 * Tracking on non-table relations
 */

create view public.not_a_table as
select *
from (
    values
        (1, 2, 3),
        (4, 5, 6),
        (7, 8, 9)
) AS not_a_table(a, b, c);

do $$ begin
    perform delta._track_nontable_relation(meta.relation_id('public','not_a_table'), array['a']);
end $$ language plpgsql;

select results_eq(
	'select 1 from delta.trackable_relation where relation_id = meta.relation_id(''public'',''not_a_table'') and primary_key_column_names = array[''a''];',
	'select 1',
	'_track_nontable_relation() adds relation to trackable_relations'
);

do $$ begin
    perform delta._untrack_nontable_relation(meta.relation_id('public','not_a_table'));
end $$ language plpgsql;

select results_ne(
	'select 1 from delta.trackable_relation where relation_id = meta.relation_id(''public'',''not_a_table'') and primary_key_column_names = array[''a''];',
	'select 1',
	'_untrack_nontable_relation() removes relation from trackable_relations'
);

-- track it again for testing
do $$ begin
    perform delta._track_nontable_relation(meta.relation_id('public','not_a_table'), array['a']);
end $$ language plpgsql;



/*
 * Tracking and untracking
 */

-- track one row
do $$ begin
    perform delta.track_untracked_row('io.pgdelta.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7'));
end $$ language plpgsql;

select ok(
	(select delta._is_newly_tracked(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7'))),
	'_is_newly_tracked() finds row added by track_untracked_row()'
);

select is(
    (select count(*)::integer from delta._get_tracked_rows_added(delta.repository_id('io.pgdelta.unittest'))),
    (select 1),
    'One tracked row after it is added.'
);


select ok(
	(select not delta._is_newly_tracked(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '8'))),
	'_is_newly_tracked() doesn''t finds untracked row'
);


-- track again
select throws_ok(
	$$ select delta.track_untracked_row('io.pgdelta.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7')); $$,
    format('Row with row_id %s is already tracked.', meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7')::text)
);


-- track a row in a non-table
do $$ begin
    perform delta.track_untracked_row('io.pgdelta.unittest', meta.row_id('public', 'not_a_table', 'a', '1'));
end $$ language plpgsql;

select ok(
	(select delta._is_newly_tracked(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('public', 'not_a_table', 'a', '1'))),
	'_is_newly_tracked() finds non-table row added by track_untracked_row()'
);



-- remove row that is tracked
do $$ begin
    perform delta.untrack_tracked_row('io.pgdelta.unittest', meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7'));
end $$ language plpgsql;

select ok(
	(select not delta._is_newly_tracked(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'periodic_table', 'AtomicNumber', '7'))),
	'_is_newly_tracked() cannot find row after removal by untrack_tracked_row()'
);


-- remove non-table row that is tracked
do $$ begin
    perform delta.untrack_tracked_row('io.pgdelta.unittest', meta.row_id('public', 'not_a_table', 'a', '1'));
end $$ language plpgsql;

select ok(
	(select not delta._is_newly_tracked(
        delta.repository_id('io.pgdelta.unittest'),
        meta.row_id('pt', 'not_a_table', 'a', '1'))),
	'_is_newly_tracked() cannot find non-table row, after removal by untrack_tracked_row()'
);

-- remove row that isn't tracked
select throws_ok(
    $$ select delta._untrack_tracked_row(delta.repository_id('io.pgdelta.unittest'), meta.row_id('pt', 'periodic_table', 'AtomicNumber', '3'::text)) $$,
    format(
        'Row with row_id %s cannot be removed because it is not tracked by supplied repository.',
        meta.row_id('pt','periodic_table','AtomicNumber','3')
    )
);



select is(
    (select count(*)::integer from delta._get_tracked_rows_added(delta.repository_id('io.pgdelta.unittest'))),
    (select 0),
    'No tracked rows after they are removed'
);
