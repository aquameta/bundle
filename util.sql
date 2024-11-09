CREATE OR REPLACE FUNCTION random_string(int) RETURNS TEXT as $$
    SELECT substr(md5(random()::text), 0, $1+1);                 
$$ language sql;  

create or replace function jsonb_merge_recurse(orig jsonb, delta jsonb)
returns jsonb language sql as $$
    select
        jsonb_object_agg(
            coalesce(keyOrig, keyDelta),
            case
                when valOrig isnull then valDelta
                when valDelta isnull then valOrig
                when (jsonb_typeof(valOrig) <> 'object' or jsonb_typeof(valDelta) <> 'object') then valDelta
                else jsonb_merge_recurse(valOrig, valDelta)
            end
        )
    from jsonb_each(orig) e1(keyOrig, valOrig)
    full join jsonb_each(delta) e2(keyDelta, valDelta) on keyOrig = keyDelta
$$;

create or replace function jsonb_deep_merge(json1 jsonb, json2 jsonb) 
returns jsonb language plpgsql as $$
declare
    result jsonb := json1;
    key text;
    value jsonb;
begin
    -- iterate through each key-value pair in the second json object
    for key, value in select * from jsonb_each(json2) loop
        -- check if the key exists in the first json object and is also a json object
        if result ? key and jsonb_typeof(result->key) = 'object' and jsonb_typeof(value) = 'object' then
            -- recursively merge sub-objects
            result := jsonb_set(result, array[key], delta.jsonb_deep_merge(result->key, value));
        else
            -- otherwise, just overwrite or add the key-value pair from json2
            result := jsonb_set(result, array[key], value);
        end if;
    end loop;
    return result;
end;
$$;
