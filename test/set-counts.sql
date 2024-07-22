---------------------------------------------------------------------------------------
--
-- DELTA TESTING FRAMEWORK
--
---------------------------------------------------------------------------------------
drop schema if exists delta_test cascade;
create schema delta_test;

set search_path=public;

create table delta_test.set_count (
    id serial primary key,
    alias text,              -- select count(*) from $set_generator_stmt
    set_generator_stmt text, -- select count(*) from $set_generator_stmt
    count integer
);

create function delta_test.create_counters() returns void as $$
declare rel record;
begin
    delete from delta_test.set_count;
    for rel in (
        -- all relations delta.*
        select name as alias, schema_name || '.' || name as set_generator_stmt from meta.relation where schema_name = 'delta' and name not in ('not_ignored_row_stmt')
        union

        -- custom function calls
        select * from (
            values
                ('commit_rows()',           'delta.commit_rows  (delta.head_commit_id(''io.aquadelta.test''))'),
                ('commit_fields()',         'delta.commit_fields(delta.head_commit_id(''io.aquadelta.test''))'),

                ('db_commit_rows()',        'delta.db_commit_rows  (delta.head_commit_id(''io.aquadelta.test''))'),
                ('db_commit_fields',        'delta.db_commit_fields(delta.head_commit_id(''io.aquadelta.test''))'),

                ('db_head_commit_rows()',   'delta.db_head_commit_rows(delta.repository_id(''io.aquadelta.test''))'),
--                ('db_head_commit_fields', 'delta.db_head_commit_fields(delta.repository_id(''io.aquadelta.test''))'),

                ('tracked_rows()',          'delta.tracked_rows(delta.repository_id(''io.aquadelta.test''))'),
                ('stage_rows()',            'delta.stage_rows  (delta.repository_id(''io.aquadelta.test''))'),

                ('untracked_rows()',        'delta.untracked_rows()'),
                ('offstage_row_deleted()',  'delta.offstage_row_deleted(delta.repository_id(''io.aquadelta.test''))')
                -- ('offstage_field_TODO',  'delta.offstage_row_deleted(delta.repository_id(''io.aquadelta.test''))')
        )
    )
    loop
        execute format ('insert into delta_test.set_count (alias, set_generator_stmt, count) select %L, %L, count(*) from %s',
            rel.alias,
            rel.set_generator_stmt,
            rel.set_generator_stmt
        );
    end loop;
end
$$ language plpgsql;


create function delta_test.refresh_counters() returns void as $$
    delete from delta_test.set_count;
    select delta_test.create_counters();
$$ language sql;

create function delta_test.count_diff () returns public.hstore as $$
declare
    old_count integer;
    _count integer;
    rel record;
    diff public.hstore := ''::public.hstore;
begin
    for rel in
        (select alias, set_generator_stmt, count from delta_test.set_count order by alias)
    loop
        execute format ('select count(*) from %s', rel.set_generator_stmt) into _count;
        execute format ('select count from delta_test.set_count where alias=%L', rel.alias) into old_count;

        -- compare, add to diff if different
        if _count != old_count then
            diff := diff operator(public.||) ((rel.alias) || '=>' || _count - old_count)::public.hstore; 
        end if;
    end loop;
    return diff;
end;
$$ language plpgsql;

-- ignore self
insert into delta.ignored_schema (schema_id) values (meta.schema_id('delta_test'));

-- make the test repo (it needs to exist before counters will work)
select delta.repository_create('io.aquadelta.test');
