------------------------------------------------------------------------------
-- HASH / UNHASH functions
------------------------------------------------------------------------------

--
-- blob
--

create table blob (
    hash text primary key not null,
    value text
--     unique(hash, value)
);
create index blob_hash_hash_index on blob using hash (hash);

-- special case for null
insert into blob ( hash, value ) values (
    '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9',
    null
);

create function create_blob( val text ) returns boolean as $$
declare
    _hash text;
begin
    _hash := bundle.hash(val);

    if val is null then
        return false;
    end if;

    if exists (select 1 from bundle.blob b where b.hash = _hash) then
        return false;
    end if;

    insert into bundle.blob (hash, value) values (_hash, val);
    return true;
end;
$$ language plpgsql;


/*
create or replace function _blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value is NULL then
            NEW.hash = '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9'::bytea;
            return NEW;
        end if;

        NEW.hash = bundle.hash(NEW.value);
        if exists (select 1 from bundle.blob b where b.hash = NEW.hash) then
            return NULL;
        end if;

        return NEW;
    end;
$$ language plpgsql;

create trigger blob_hash_update
    before insert or update on blob
    for each row execute procedure _blob_hash_gen_trigger();
*/


/*
Get hash of a text value.
If the value is longer than the length of a hash (32 chars) then just store the
value.  Otherwise store the sha256 hash of the value.
Maybe just ditch this stupid optimization.
*/

create or replace function hash( value text ) returns text as $$
begin
/*
    if length(value) < 32 then -- length(public.digest('foo','sha256')) then
        return value;
    end if;
*/
    if value is null then
        return '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9';
    end if;

    return public.digest(value, 'sha256');
end;
$$ language plpgsql;


-- Lookup the text value corresponding to supplied hash, in the blob table.
create or replace function unhash( _hash text ) returns text as $$
declare
    val text;
begin
    /*
    if length(_hash) < 32 then -- length(public.digest('foo','sha256')) then
        return _hash;
    end if;
    */

    if _hash is null then
        return '\xc0178022ef029933301a5585abee372c28ad47d08e3b5b6b748ace8e5263d2c9';
    end if;

    if not exists (select 1 from bundle.blob b where b.hash = _hash) then
        raise exception 'unhash(): hash % has no blob.', _hash;
    end if;

    select value into val from bundle.blob where hash = _hash;
    return val;
end;
$$ language plpgsql;


/*
build a jsonb object from record that contains the record's keys as columns and
a hash of the records value as the key's value.
*/

create or replace function row_to_jsonb_hash_obj(
    rec record,
    create_blob boolean default false, -- should the blob be created (if necessary) in the blob table?
    columns text[] default null -- the columns in this record (optimization so we can skip pg_catalog lookup per-row)
) returns jsonb as $$
declare
    hash_obj jsonb := '{}';
    col text;
    val text;
begin
    -- TODO: only look up row's column names, if not supplied
    if columns is null then
        select
            array_agg(
                a.attname
                -- format_type(a.atttypid, a.atttypmod) as data_type,
                -- a.attnum as "position"
                order by a.attnum
            )
            from pg_attribute a
            where a.attrelid = (
                select typrelid from pg_type where oid = pg_typeof(rec)::oid
            )
            and a.attnum > 0
            and not a.attisdropped
        into columns;
    end if;

    -- raise notice 'columns: %', columns;

    -- create the object
    foreach col in array columns loop
        execute format('select to_jsonb(($1).%I)::text', col)
        into val
        using rec;

        hash_obj := hash_obj || jsonb_build_object(col, bundle.hash(val));

        -- create the blob?
        if create_blob then
            perform bundle.create_blob(val);
        end if;
    end loop;

    return hash_obj;
end;
$$ language plpgsql;

