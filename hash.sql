------------------------------------------------------------------------------
-- HASH / UNHASH functions
------------------------------------------------------------------------------

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
    if length(hash) < 32 then -- length(public.digest('foo','sha256')) then
        return hash;
    else
        select value into val from delta.blob where hash = _hash;
        return val;
    end if;
end;
$$ language plpgsql;
