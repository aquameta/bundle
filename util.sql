------------------------------------------------------------------------------
-- UTIL / MISC FUNCTIONS
-- General purpose utils that probably belong somewhere else.
------------------------------------------------------------------------------

--
-- random_string()
--

CREATE OR REPLACE FUNCTION random_string( int ) RETURNS TEXT as $$
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
                else bundle.jsonb_merge_recurse(valOrig, valDelta)
            end
        )
    from jsonb_each(orig) e1(keyOrig, valOrig)
    full join jsonb_each(delta) e2(keyDelta, valDelta) on keyOrig = keyDelta
$$;


-- jsonb_merge
--

-- https://www.tyil.nl/post/2020/12/15/merging-json-in-postgresql/
CREATE OR REPLACE FUNCTION jsonb_merge( original jsonb, delta jsonb ) RETURNS jsonb AS $$
    DECLARE result jsonb;
    BEGIN
    SELECT
        json_object_agg(
            COALESCE(original_key, delta_key),
            CASE
                WHEN original_value IS NULL THEN delta_value
                WHEN delta_value IS NULL THEN original_value
                WHEN (jsonb_typeof(original_value) <> 'object' OR jsonb_typeof(delta_value) <> 'object') THEN delta_value
                ELSE bundle.jsonb_merge(original_value, delta_value)
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

create or replace function clock_diff( start_time timestamp ) returns text as $$
    select round(extract(epoch from (clock_timestamp() - start_time))::numeric, 3) as seconds;
$$ language sql;


--
-- array_reverse()
--

-- https://wiki.postgresql.org/wiki/Array_reverse
create or replace function array_reverse( anyarray ) returns anyarray as $$
select array(
    select $1[i]
        from generate_subscripts($1,1) as s(i)
            order by i desc
            );
$$ language 'sql' strict immutable;


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
-- row_to_jsonb_text()
--

-- TODO: This is the main row serializer.  Right now it's just handing off to
-- to_jsonb(), but to_jsonb() converts arrays, composite types and numbers to
-- non-text values.  we need a function that takes a record and does to_jsonb
-- except produces a flat object with all text values instead.

create or replace function row_to_jsonb_text( input_record anyelement )
returns jsonb as $$
    select to_jsonb(input_record);
    /*
    from (
        select key, value
        from jsonb_each_text(to_jsonb(input_record))
    ) subquery;
    */
$$
language sql stable;
