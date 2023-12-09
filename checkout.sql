------------------------------------------------------------------------------
-- CHECKOUT
------------------------------------------------------------------------------

/*
create function checkout( _commit_id uuid ) returns text as $$
with recursive ancestry as (
    select c.id, c.parent_id, c.message, 1 as position from commit c where c.id = _commit_id
    union
    select c.id, c.parent_id, c.message, a.position+1 as position from commit c join ancestry a on c.id = a.parent_id
)
-- rows added
select ra.row_id
    from ancestry a
    join row_added ra on ra.commit_id = a.commit_id
    join row_deleted rd on rd.row_id = ra.ra.row_id on
except
-- rows deleted after they were added
select ra.row_id
    join row_deleted rd on
    from ancestry a
    join row_added ra on ra.commit_id = a.commit_id
return 'ok';
end
$$ language sql;
*/

