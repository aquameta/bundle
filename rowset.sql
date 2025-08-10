create or replace function _get_rowset_relations(rowset jsonb) returns meta.relation_id[] as $$
    select array_agg(distinct relation_id) from (
        select meta.row_id_to_relation_id(x::jsonb) as relation_id from jsonb_array_elements(rowset) el(x)
    ) y;
$$ language sql;
