--
-- ignore self, system catalogs, internal schemas, public
--

do $$
    declare r record;
    begin
        for r in
            -- ignore all internal tables, except for ignore rules, which are version-controlled.
            select * from meta.table where schema_name = 'ditty' and name not like 'ignored%'
        loop
            insert into ditty.ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
        end loop;

        -- ignore system catalogs, pg_temp*, pg_toast*
        for r in
            select * from meta.schema
                where name in ('pg_catalog','information_schema')
                    or name like 'pg_toast%'
                    or name like 'pg_temp%'
        loop
            insert into ditty.ignored_schema(schema_id) values (meta.schema_id(r.name));
        end loop;
    end;
$$ language plpgsql;


-- track the ignore rules in the core ditty repo
do $$
    begin
        perform ditty.create_repository('io.ditty.core.repository');
        perform ditty.track_untracked_row('io.ditty.core.repository', meta.row_id('ditty','ignored_table','id',id::text)) from ditty.ignored_table;
        perform ditty.track_untracked_row('io.ditty.core.repository', meta.row_id('ditty','ignored_schema','id',id::text)) from ditty.ignored_schema;

        perform ditty.stage_tracked_rows('io.ditty.core.repository');
        perform ditty.commit('io.ditty.core.repository', 'Ignore rules.', 'Eric Hanson', 'eric@aquameta.com');
    end;
$$ language plpgsql;
