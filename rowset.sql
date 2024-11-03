create or replace function _get_rowset_relations(rowset jsonb) returns meta.relation_id[] as $$
    select array_agg(distinct x) from (
        select x::meta.row_id::meta.relation_id from jsonb_array_elements_text(rowset) el(x)
    ) y;
$$ language sql;
