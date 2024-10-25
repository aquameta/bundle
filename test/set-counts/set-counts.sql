---------------------------------------------------------------------------------------
--
-- DELTA TESTING FRAMEWORK
--
---------------------------------------------------------------------------------------
drop schema if exists set_counts cascade;
create schema set_counts;

create extension if not exists hstore schema public;
create extension if not exists pgtap schema public;


set search_path=public;

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
        -- all relations delta.*
        select name as alias, schema_name || '.' || name as set_generator_stmt from meta.relation where schema_name = 'delta' and name not in ('not_ignored_row_stmt')
        union

        -- custom function calls
        select * from (
            values
                ('commit_rows',             'delta._get_commit_rows  (delta.head_commit_id(''io.pgdelta.set_counts''))'),
                ('commit_fields',           'delta._get_commit_fields(delta.head_commit_id(''io.pgdelta.set_counts''))'),

                ('db_commit_rows',          'delta._get_db_commit_rows  (delta.head_commit_id(''io.pgdelta.set_counts''))'),
                ('db_commit_fields',        'delta._get_db_commit_fields(delta.head_commit_id(''io.pgdelta.set_counts''))'),

                ('db_head_commit_rows',     'delta._get_db_head_commit_rows(delta.repository_id(''io.pgdelta.set_counts''))'),
--                ('db_head_commit_fields',    'delta._get_db_head_commit_fields(delta.repository_id(''io.pgdelta.set_counts''))'),

                ('tracked_rows',            'delta._get_tracked_rows(delta.repository_id(''io.pgdelta.set_counts''))'),
                ('stage_rows',              'delta._get_stage_rows  (delta.repository_id(''io.pgdelta.set_counts''))'),

                ('untracked_rows',          'delta._get_untracked_rows()'),
                ('offstage_deleted_rows',   'delta._get_offstage_deleted_rows(delta.repository_id(''io.pgdelta.set_counts''))'),
                ('offstage_changed_fields', 'delta._get_offstage_updated_fields(delta.repository_id(''io.pgdelta.set_counts''))')
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
begin
    for rel in
        (select alias, set_generator_stmt, count from set_counts.set_count order by alias)
    loop
        execute format ('select count(*) from %s', rel.set_generator_stmt) into _count;
        execute format ('select count from set_counts.set_count where alias=%L', rel.alias) into old_count;

        -- compare, add to diff if different
        if _count != old_count then
            diff := diff operator(public.||) ((rel.alias) || '=>' || _count - old_count)::public.hstore; 
        end if;
    end loop;
    return diff;
end;
$$ language plpgsql;

-- ignore self
insert into delta.ignored_schema (schema_id) values (meta.schema_id('set_counts'));

-- create testing schema
select delta.create_repository('io.pgdelta.set_counts');
