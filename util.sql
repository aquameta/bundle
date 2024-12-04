------------------------------------------------------------------------------
-- UTIL / MISC FUNCTIONS
-- General purpose utils that probably belong somewhere else.
------------------------------------------------------------------------------

--
-- random_string()
--

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
                else ditty.jsonb_merge_recurse(valOrig, valDelta)
            end
        )
    from jsonb_each(orig) e1(keyOrig, valOrig)
    full join jsonb_each(delta) e2(keyDelta, valDelta) on keyOrig = keyDelta
$$;

--
-- jsonb_deep_merge()
--
-- via chatGPT
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
            result := jsonb_set(result, array[key], ditty.jsonb_deep_merge(result->key, value));
        else
            -- otherwise, just overwrite or add the key-value pair from json2
            result := jsonb_set(result, array[key], value);
        end if;
    end loop;
    return result;
end;
$$;


--
-- jsonb_merge
--

-- https://www.tyil.nl/post/2020/12/15/merging-json-in-postgresql/
CREATE OR REPLACE FUNCTION jsonb_merge(original jsonb, delta jsonb) RETURNS jsonb AS $$
    DECLARE result jsonb;
    BEGIN
    SELECT
        json_object_agg(
            COALESCE(original_key, delta_key),
            CASE
                WHEN original_value IS NULL THEN delta_value
                WHEN delta_value IS NULL THEN original_value
                WHEN (jsonb_typeof(original_value) <> 'object' OR jsonb_typeof(delta_value) <> 'object') THEN delta_value
                ELSE ditty.jsonb_merge(original_value, delta_value)
            END
        )
        INTO result
        FROM jsonb_each(original) e1(original_key, original_value)
        FULL JOIN jsonb_each(delta) e2(delta_key, delta_value) ON original_key = delta_key;
    RETURN result;
END
$$ LANGUAGE plpgsql;


--
-- clock_diff()
--

create or replace function clock_diff(start_time timestamp) returns text as $$
    select round(extract(epoch from (clock_timestamp() - start_time))::numeric, 3) as seconds;
$$ language sql;


--
-- array_reverse()
--

-- https://wiki.postgresql.org/wiki/Array_reverse
CREATE OR REPLACE FUNCTION array_reverse(anyarray) RETURNS anyarray AS $$
SELECT ARRAY(
    SELECT $1[i]
        FROM generate_subscripts($1,1) AS s(i)
            ORDER BY i DESC
            );
$$ LANGUAGE 'sql' STRICT IMMUTABLE;


create or replace function exec(statements text[]) returns setof record as $$
   declare
       statement text;
   begin
       foreach statement in array statements loop
           raise debug 'EXEC statement: %', statement;
           return query execute statement;
       end loop;
    end;
$$ language plpgsql volatile returns null on null input;


--
-- query_to_jsonb_text()
--

create or replace function query_to_jsonb_text(query text)
returns jsonb language plpgsql as $$
declare
    result_row jsonb;
begin
    -- execute the query and convert the result row to jsonb
    execute format('select to_jsonb(t)::jsonb from (%s) as t', query) into result_row;

    return (
        select jsonb_object_agg(
            key,
            /*
            case
                when jsonb_typeof(value) in ('string', 'array', 'object') then value--::text::jsonb
                else value
            end
            */
            value
        ) from jsonb_each(result_row)
    );
end;
$$;


--
-- row_to_jsonb_text()
--

create or replace function row_to_jsonb_text(input_record anyelement)
returns jsonb language sql stable as $$
    select jsonb_object_agg(key, value::text)
    from (
        select key, value
        from jsonb_each_text(to_jsonb(input_record))
    ) subquery;
$$;
