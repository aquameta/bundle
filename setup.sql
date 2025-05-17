--
-- ignore self, system catalogs, internal schemas, public
--

do $$
    declare r record;
    begin
        for r in
            -- ignore all internal tables, except for ignore rules, which are version-controlled.
            select * from meta.table where schema_name = 'bundle' and name not like 'ignored%'
        loop
            insert into bundle.ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
        end loop;

        -- ignore system catalogs, pg_temp*, pg_toast*
        for r in
            select * from meta.schema
                where name in ('pg_catalog','information_schema')
                    or name like 'pg_toast%'
                    or name like 'pg_temp%'
        loop
            insert into bundle.ignored_schema(schema_id) values (meta.schema_id(r.name));
        end loop;
    end;
$$ language plpgsql;


-- track the ignore rules in the core bundle repo
do $$
    begin
        perform bundle.create_repository('io.bundle.core.repository');
        perform bundle.track_untracked_row('io.bundle.core.repository', meta.row_id('bundle','ignored_table','id',id::text)) from bundle.ignored_table;
        perform bundle.track_untracked_row('io.bundle.core.repository', meta.row_id('bundle','ignored_schema','id',id::text)) from bundle.ignored_schema;

        perform bundle.stage_tracked_rows('io.bundle.core.repository');
        perform bundle.commit('io.bundle.core.repository', 'Ignore rules.', 'Eric Hanson', 'eric@aquameta.com');
    end;
$$ language plpgsql;
