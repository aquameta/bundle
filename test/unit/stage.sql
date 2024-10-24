select '------------ stage.sql -----------------------------------------------';
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

select delta.status();

-- track and stage one row
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform delta.tracked_row_add(
            'io.pgdelta.unittest',
            row_id
        );

        perform delta.stage_row_add(
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
-- _get_stage_rows_added()
--

select results_eq(
   $$ select row_id::text from delta._get_stage_rows_added(delta.repository_id('io.pgdelta.unittest')) $$,
   array['(pt,periodic_table,{AtomicNumber},{1})'],
   '_get_stage_rows_added() finds staged row'
);


do $$ begin
    -- commit the single row change
    perform delta.commit('io.pgdelta.unittest', 'first element', 'Test User', 'test@example.com');
    -- update pt.periodic_table set "Discoverer" = 'Don Henley' where "AtomicNumber" = 1;
end; $$ language plpgsql;

select results_eq(
   $$ select row_id::text from delta._get_stage_rows_added(delta.repository_id('io.pgdelta.unittest')) $$,
   array[]::text[],
   '_get_stage_rows_added() does not find staged row after commit.'
);

select delta.status();


--
-- stage_row_delete()
--

-- stage delete of commited row
do $$
    declare
        row_id meta.row_id := meta.row_id('pt', 'periodic_table', 'AtomicNumber', '1');
    begin
        perform delta.stage_row_delete(
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
        perform delta.tracked_row_add(
            'io.pgdelta.unittest',
            meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text)
        )
        from pt.periodic_table where "AtomicNumber" = 1;

        perform delta.stage_row_add(
            'io.pgdelta.unittest',
            meta.row_id('pt','periodic_table','AtomicNumber', "AtomicNumber"::text)
        ) from pt.periodic_table where "AtomicNumber" = 1;

    end;
$$ language plpgsql;
*/


/*
-- fails because row not tracked

select delta.stage_row_add('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text))
    from shakespeare.character where name ilike 'a%' order by name limit 1;
*/
-----------------------------------------------------------
-- stage again
select throws_ok(
    $$ select delta.stage_row_add('io.pgdelta.unittest', meta.row_id('shakespeare', 'character', 'id', id::text)) from shakespeare.character where name ilike 'a%' order by name limit 1; $$,
    format('Row with row_id %s is already staged.', meta.row_id('shakespeare', 'character', 'id', 'Aaron')),
    'Staging an already staged row throws exception'
);



/*
create or replace function _unstage_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_name text, pk_value text )
create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
create or replace function _stage_field_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
create or replace function _get_stage_rows_added( _repository_id uuid ) returns table (repository_id uuid,row_id meta.row_id) as $$
create or replace function _get_stage_rows_deleted( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
create or replace function _get_stage_fields_changed( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
create or replace function _get_untracked_rows(_relation_id meta.relation_id default null) returns setof meta.row_id as $$
create or replace function _get_tracked_rows( _repository_id uuid ) returns setof meta.row_id as $$
create or replace function _get_offstage_rows_deleted( _repository_id uuid ) returns setof meta.row_id as $$
create or replace function _get_offstage_fields_changed( _repository_id uuid ) returns setof delta.field_hash as $$
create or replace function _get_stage_rows( _repository_id uuid ) returns setof stage_row as $$
create or replace function _track_relation_rows( repository_id uuid, _relation_id meta.relation_id ) returns void as $$ -- returns setof uuid?
create or replace function track_relation_rows( repository_name text, schema_name text, relation_name text ) returns void as $$ -- setof uuid?
create or replace function _stage_tracked_rows( _repository_id uuid ) returns void as $$
create or replace function stage_tracked_rows( repository_name text ) returns void as $$
create or replace function _stage_field_changes( _repository_id uuid ) returns void as $$
create or replace function stage_field_changes( repository_name text ) returns void as $$
*/
