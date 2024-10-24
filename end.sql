--
-- ignore self, system catalogs, internal schemas, public
--

do $$
    declare r record;
    begin
        for r in
            -- ignore all internal tables, except for ignore rules, which are version-controlled.
            select * from meta.table where schema_name = 'delta' and name not like 'ignored%'
        loop
            insert into delta.ignored_table(relation_id) values (meta.relation_id(r.schema_name, r.name));
        end loop;

        -- ignore system catalogs, pg_temp*, pg_toast*
        for r in
            select * from meta.schema
                where name in ('pg_catalog','information_schema')
                    or name like 'pg_toast%'
                    or name like 'pg_temp%'
        loop
            insert into delta.ignored_schema(schema_id) values (meta.schema_id(r.name));
        end loop;
    end;
$$ language plpgsql;


-- track the ignore rules in the core delta repo
do $$
    begin
        perform delta.create_repository('io.aquadelta.core.repository');
        perform delta.track_untracked_row('io.aquadelta.core.repository', meta.row_id('delta','ignored_table','id',id::text)) from delta.ignored_table;
        perform delta.track_untracked_row('io.aquadelta.core.repository', meta.row_id('delta','ignored_schema','id',id::text)) from delta.ignored_schema;

        perform delta.stage_tracked_rows('io.aquadelta.core.repository');
        perform delta.commit('io.aquadelta.core.repository', 'Ignore rules.', 'Eric Hanson', 'eric@aquameta.com');
    end;
$$ language plpgsql;

commit;
