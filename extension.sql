-- flag all tables as available for pg_dump to dump
select pg_catalog.pg_extension_config_dump('blob','');
select pg_catalog.pg_extension_config_dump('commit','');
select pg_catalog.pg_extension_config_dump('ignored_column','');
select pg_catalog.pg_extension_config_dump('ignored_row','');
select pg_catalog.pg_extension_config_dump('ignored_schema','');
select pg_catalog.pg_extension_config_dump('ignored_table','');
select pg_catalog.pg_extension_config_dump('not_ignored_row_stmt','');
select pg_catalog.pg_extension_config_dump('repository','');
select pg_catalog.pg_extension_config_dump('stage_field_to_change','');
select pg_catalog.pg_extension_config_dump('stage_row_to_add','');
select pg_catalog.pg_extension_config_dump('stage_row_to_remove','');
select pg_catalog.pg_extension_config_dump('trackable_nontable_relation','');
select pg_catalog.pg_extension_config_dump('trackable_relation','');
select pg_catalog.pg_extension_config_dump('tracked_query','');
select pg_catalog.pg_extension_config_dump('tracked_row_added','');
