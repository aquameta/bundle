---------------------------------------------------------------------------------------
--
-- DELTA TESTING FRAMEWORK
--
---------------------------------------------------------------------------------------
create schema set_counts;

create table set_counts.set_count (
    id serial primary key,
    alias text,              -- select count(*) from $set_generator_stmt
    set_generator_stmt text, -- select count(*) from $set_generator_stmt
    count integer
);

create or replace function set_counts.create_counters() returns void as $$
declare rel record;
begin
    delete from set_counts.set_count;
    for rel in (
        -- all relations ditty.*
        select name as alias, schema_name || '.' || name as set_generator_stmt from meta.relation where schema_name = 'ditty' and name in ('ZZZ') -- not in ('not_ignored_row_stmt')

        union

        -- custom function calls
        select * from (
            values
/*
                ('commit_rows',             'ditty._get_commit_rows  (ditty.head_commit_id(''io.pgditty.set_counts''))'),
                ('commit_fields',           'ditty._get_commit_fields(ditty.head_commit_id(''io.pgditty.set_counts''))'),

                ('db_commit_rows',          'ditty._get_db_commit_rows  (ditty.head_commit_id(''io.pgditty.set_counts''))'),
                ('db_commit_fields',        'ditty._get_db_commit_fields(ditty.head_commit_id(''io.pgditty.set_counts''))'),

                ('db_head_commit_rows',     'ditty._get_db_head_commit_rows(ditty.repository_id(''io.pgditty.set_counts''))'),
                ('db_head_commit_fields',   'ditty._get_db_head_commit_fields(ditty.repository_id(''io.pgditty.set_counts''))'),

                ('tracked_rows',            'ditty._get_tracked_rows(ditty.repository_id(''io.pgditty.set_counts''))'),
                ('stage_rows',              'ditty._get_stage_rows  (ditty.repository_id(''io.pgditty.set_counts''))'),

                ('untracked_rows',          'ditty._get_untracked_rows()'),
                ('offstage_deleted_rows',   'ditty._get_offstage_deleted_rows(ditty.repository_id(''io.pgditty.set_counts''))'),
                ('offstage_changed_fields', 'ditty._get_offstage_updated_fields(ditty.repository_id(''io.pgditty.set_counts''))')
*/


('commit_ancestry',              'ditty._get_commit_ancestry(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
('commit_fields',                'ditty._get_commit_fields(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
-- BROKEN:
-- ('commit_jsonb_fields',          'ditty._get_commit_jsonb_fields(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
-- ('commit_jsonb_rows',            'ditty._get_commit_jsonb_rows(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
('commit_row_count_by_relation', 'ditty._get_commit_row_count_by_relation(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
-- REDUNDANT:
-- ('commit_rows',                  'ditty._get_commit_rows(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
-- ('db_commit_fields',             'ditty._get_db_commit_fields(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
-- ('db_commit_rows',               'ditty._get_db_commit_rows(ditty.head_commit_id(''org.opensourceshakespeare.db''))'),
('db_head_commit_fields',        'ditty._get_db_head_commit_fields(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('db_head_commit_rows',          'ditty._get_db_head_commit_rows(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('db_stage_fields_to_change',    'ditty._get_db_stage_fields_to_change(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('head_commit_fields',           'ditty._get_head_commit_fields(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('head_commit_rows',             'ditty._get_head_commit_rows(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('offstage_deleted_rows',        'ditty._get_offstage_deleted_rows(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('offstage_updated_fields',      'ditty._get_offstage_updated_fields(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('stage_fields_to_change',       'ditty._get_stage_fields_to_change(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('stage_rows',                   'ditty._get_stage_rows(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('stage_rows_to_add',            'ditty._get_stage_rows_to_add(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('stage_rows_to_remove',         'ditty._get_stage_rows_to_remove(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('tracked_rows',                 'ditty._get_tracked_rows(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('tracked_rows_added',           'ditty._get_tracked_rows_added(ditty.repository_id(''org.opensourceshakespeare.db''))'),
('untracked_rows',               'ditty._get_untracked_rows()')

        )
    )
    loop
        execute format ('insert into set_counts.set_count (alias, set_generator_stmt, count) select %L, %L, count(*) from %s',
            rel.alias,
            rel.set_generator_stmt,
            rel.set_generator_stmt
        );
    end loop;
end
$$ language plpgsql;


create or replace function set_counts.refresh_counters() returns void as $$
    delete from set_counts.set_count;
    select set_counts.create_counters();
$$ language sql;

create or replace function set_counts.count_diff () returns public.hstore as $$
declare
    old_count integer;
    _count integer;
    rel record;
    diff public.hstore := ''::public.hstore;
    diff_time timestamp;
begin
    diff_time := clock_timestamp();
    raise notice 'set_counts performance profile:';
    for rel in
        (select alias, set_generator_stmt, count from set_counts.set_count order by alias)
    loop
        execute format ('select count(*) from %s', rel.set_generator_stmt) into _count;
        execute format ('select count from set_counts.set_count where alias=%L', rel.alias) into old_count;

        -- compare, add to diff if different
        if _count != old_count then
            diff := diff operator(public.||) ((rel.alias) || '=>' || _count - old_count)::public.hstore; 
        end if;

        -- display time
        raise notice '  - %: %s', rel.alias, ditty.clock_diff(diff_time);
        diff_time := clock_timestamp();
    end loop;
    return diff;
end;
$$ language plpgsql;

-- ignore self
insert into ditty.ignored_schema (schema_id) values (meta.schema_id('set_counts'));

-- create testing schema
select ditty.create_repository('io.pgditty.set_counts');
