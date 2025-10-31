-- semver-in-sql.sql
-- a sql-only semver implementation using a text domain + plpgsql compare + btree opclass
-- adapted from https://github.com/theory/pg-semver

-- 1) domain with semver 2.0.0 validation (build metadata allowed but ignored for ordering)
--   - major.minor.patch are non-negative integers without leading zeros (except "0")
--   - pre-release: dot-separated identifiers, each alnum/hyphen, no empty identifiers
--   - build: dot-separated identifiers, free-form alnum/hyphen
create domain bundle.version as text
    check (
        value ~
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' -- x.y.z
        '(-([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?'              -- -prerelease
        '(\+([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$'            -- +build
    );

-- helpers

create or replace function bundle._split_build(s text)
returns text language sql immutable strict as $$
    select split_part(s, '+', 1)
$$;

create or replace function bundle._split_prerelease(s text)
returns text language sql immutable strict as $$
    select
        case
            when position('-' in s) = 0 then null
            else split_part(split_part(s, '+', 1), '-', 2)
        end
$$;

create or replace function bundle._split_core(s text)
returns text language sql immutable strict as $$
    select split_part(split_part(s, '+', 1), '-', 1)
$$;

create or replace function bundle.major(s bundle.version)
returns int language sql immutable strict as $$
    select split_part(bundle._split_core(s::text), '.', 1)::int
$$;

create or replace function bundle.minor(s bundle.version)
returns int language sql immutable strict as $$
    select split_part(bundle._split_core(s::text), '.', 2)::int
$$;

create or replace function bundle.patch(s bundle.version)
returns int language sql immutable strict as $$
    select split_part(bundle._split_core(s::text), '.', 3)::int
$$;

create or replace function bundle.prerelease(s bundle.version)
returns text language sql immutable as $$
    select bundle._split_prerelease(s::text)
$$;

-- prerelease comparator per semver 2.0.0:
-- - null (no prerelease) > any prerelease
-- - compare dot-identifiers left-to-right
-- - numeric vs numeric: numeric compare
-- - numeric vs non-numeric: numeric < non-numeric
-- - if all equal but one has more identifiers, longer wins
create or replace function bundle._cmp_prerelease(a text, b text)
returns int language plpgsql immutable as $$
declare
    aa text[] := case when a is null then null else regexp_split_to_array(a, '\.') end;
    bb text[] := case when b is null then null else regexp_split_to_array(b, '\.') end;
    i  int;
    na boolean;
    nb boolean;
    ia bigint;
    ib bigint;
begin
    -- no prerelease beats prerelease
    if aa is null and bb is null then
        return 0;
    elsif aa is null then
        return 1; -- release > prerelease
    elsif bb is null then
        return -1;
    end if;

    for i in 1..greatest(coalesce(array_length(aa,1),0), coalesce(array_length(bb,1),0)) loop
        if i > coalesce(array_length(aa,1),0) then
            -- a ran out -> b has more identifiers -> b greater -> a < b
            return -1;
        elsif i > coalesce(array_length(bb,1),0) then
            return 1;
        end if;

        na := aa[i] ~ '^[0-9]+$';
        nb := bb[i] ~ '^[0-9]+$';

        if na and nb then
            ia := aa[i]::bigint;
            ib := bb[i]::bigint;
            if ia < ib then return -1; end if;
            if ia > ib then return 1; end if;
        elsif na and not nb then
            return -1; -- numeric < non-numeric
        elsif not na and nb then
            return 1;  -- non-numeric > numeric
        else
            if aa[i] < bb[i] then return -1; end if;
            if aa[i] > bb[i] then return 1; end if;
        end if;
    end loop;

    return 0;
end;
$$;

-- main comparator: compare core first (major/minor/patch), then prerelease
create or replace function bundle.cmp(a bundle.version, b bundle.version)
returns int language plpgsql immutable strict as $$
declare
    ma int := bundle.major(a);
    mb int := bundle.major(b);
    na int := bundle.minor(a);
    nb int := bundle.minor(b);
    pa int := bundle.patch(a);
    pb int := bundle.patch(b);
    ra int;
begin
    if ma <> mb then
        return case when ma < mb then -1 else 1 end;
    end if;

    if na <> nb then
        return case when na < nb then -1 else 1 end;
    end if;

    if pa <> pb then
        return case when pa < pb then -1 else 1 end;
    end if;

    ra := bundle._cmp_prerelease(bundle.prerelease(a), bundle.prerelease(b));
    return ra;
end;
$$;

-- equality consistent with cmp (ignores build metadata)
create or replace function bundle.eq(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select bundle.cmp(a, b) = 0
$$;

create or replace function bundle.ne(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select not bundle.eq(a, b)
$$;

create or replace function bundle.lt(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select bundle.cmp(a, b) < 0
$$;

create or replace function bundle.le(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select bundle.cmp(a, b) <= 0
$$;

create or replace function bundle.gt(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select bundle.cmp(a, b) > 0
$$;

create or replace function bundle.ge(a bundle.version, b bundle.version)
returns boolean language sql immutable strict as $$
    select bundle.cmp(a, b) >= 0
$$;

-- operators
create operator =  (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.eq, commutator = =, negator = <>, restrict = eqsel, join = eqjoinsel);
create operator <> (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.ne, commutator = <>, negator = =, restrict = neqsel, join = neqjoinsel);
create operator <  (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.lt, restrict = scalarltsel, join = scalarltjoinsel);
create operator <= (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.le, restrict = scalarltsel, join = scalarltjoinsel);
create operator >  (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.gt, restrict = scalargtsel, join = scalargtjoinsel);
create operator >= (leftarg = bundle.version, rightarg = bundle.version, procedure = bundle.ge, restrict = scalargtsel, join = scalargtjoinsel);

-- btree opclass so normal btree indexes work on the domain
-- if your postgres forbids opclass on a domain, see the fallback note below.
create operator class bundle.btree_semver_ops default for type bundle.version using btree as
    operator 1 <  (bundle.version, bundle.version),
    operator 2 <= (bundle.version, bundle.version),
    operator 3 =  (bundle.version, bundle.version),
    operator 4 >= (bundle.version, bundle.version),
    operator 5 >  (bundle.version, bundle.version),
    function 1 bundle.cmp(bundle.version, bundle.version);

-- optional: canonicalization function (drops build metadata) if you want a normalized “key”
create or replace function bundle.canonical(s bundle.version)
returns bundle.version language sql immutable strict as $$
    select bundle._split_build(s::text)::bundle.version
$$;

-- quick tests
-- select bundle.cmp('1.2.3'::bundle.version, '1.2.3-alpha'::bundle.version);   -- > 0
-- select bundle.cmp('1.2.3-alpha.9', '1.2.3-alpha.10');                         -- -1 (numeric compare)
-- select bundle.cmp('1.2.3-alpha.1', '1.2.3-alpha.beta');                       -- -1 (numeric < non-numeric)
-- select '1.2.3'::bundle.version < '1.10.0'::bundle.version;                    -- true

-- indexing example
-- create table t (v bundle.version not null);
-- create index on t using btree (v);  -- uses bundle.btree_semver_ops
-- explain analyze select * from t where v >= '2.0.0'::bundle.version;

