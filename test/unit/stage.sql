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

-- track first 20 elements
do $$
    begin
        perform delta.tracked_row_add(
            'io.pgdelta.unittest',
            meta.row_id('pt', 'periodic_table', 'AtomicNumber', "AtomicNumber"::text)
        )
        from pt.periodic_table where "AtomicNumber" < 20;
    end;
$$ language plpgsql;
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
create or replace function _stage_row_add( _repository_id uuid, _row_id meta.row_id ) returns void as $$
create or replace function stage_row_add( repository_name text, row_id meta.row_id )
create or replace function _stage_row_delete( _repository_id uuid, _row_id meta.row_id ) returns void as $$
create or replace function stage_row_delete( repository_name text, row_id meta.row_id )
create or replace function _unstage_row( _repository_id uuid, _row_id meta.row_id ) returns void as $$
create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_name text, pk_value text )
create or replace function unstage_row( _repository_id uuid, schema_name text, relation_name text, pk_column_names text[], pk_values text[] )
create or replace function _stage_field_change( _repository_id uuid, _field_id meta.field_id ) returns boolean as $$
create or replace function _get_stage_rows_added( _repository_id uuid ) returns table (repository_id uuid,row_id meta.row_id) as $$
create or replace function _get_stage_rows_deleted( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
create or replace function _get_stage_fields_changed( _repository_id uuid ) returns table(repository_id uuid, row_id meta.row_id) as $$
create or replace function _is_staged( row_id meta.row_id ) returns boolean as $$
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