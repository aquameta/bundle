------------------------------------------------------------------------------
-- PRIMITIVE TYPES
------------------------------------------------------------------------------

--
-- blob
--

/*
If the value is longer than the length of a hash (32 chars) then just store the
value.  Otherwise store the sha256 hash of the value.
*/

create or replace function hash( value text ) returns text as $$
begin
    if length(value) < 32 then -- length(public.digest('foo','sha256')) then
        return value;
    else
        return public.digest(value, 'sha256');
    end if;
end;
$$ language plpgsql;

create or replace function unhash( _hash text ) returns text as $$
declare
    val text;
begin
    if length(_hash) < 32 then -- length(public.digest('foo','sha256')) then
        return _hash;
    else
        select value into val from delta.blob where hash = _hash;
        return val;
    end if;
end;
$$ language plpgsql;

--
-- blob/hash table
--

create table blob (
    hash text primary key not null,
    value text,
    unique(hash, value)
);
create index blob_hash_hash_index on blob using hash (hash);


create or replace function _blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value is NULL then
            NEW.hash = '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9'::bytea;
            return NEW;
        end if;

        NEW.hash = delta.hash(NEW.value);
        if exists (select 1 from delta.blob b where b.hash = NEW.hash) then
            return NULL;
        end if;

        return NEW;
    end;
$$ language plpgsql;

create trigger blob_hash_update
    before insert or update on blob
    for each row execute procedure _blob_hash_gen_trigger();


--
-- delta_row object
--

/*
 * `delta_row` is a composite type that maps a `meta.row_id` to a set of
 * key:value strings, represented as an `hstore`.  Keys are column names on the
 * row, and values can be either a literal value, or a value hash.
 */

create type delta_row as (row_id meta.row_id, fields public.hstore);

create function delta_row(row_id meta.row_id, fields public.hstore) returns delta_row as $$
    select row(row_id, fields);
$$ language sql;


--
-- value
--
/*
 * A field_id plus a value, the literal value of a single row+column.
 */

create type value as (
    schema_name text,
    relation_name text, 
    pk_column_names text[],
    pk_values text[],
    column_name text,
    value text
);

create function value ( schema_name text, relation_name text, pk_column_names text[], pk_values text[], column_name text, value text )
returns delta.value as $$
    select row(schema_name, relation_name, pk_column_names, pk_values, column_name, value);
$$ language sql;

create function value (row_id meta.row_id, column_name text, value text) returns delta.value as $$
    select row((row_id).schema_name, (row_id).relation_name, (row_id).pk_column_names, (row_id).pk_values, column_name, value);
$$ language sql;


