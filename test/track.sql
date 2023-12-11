-----------------------------------------------------------

select delta.repository_create('org.opensourceshakespeare.db');

-- track one row
select delta.track_row('org.opensourceshakespeare.db', 'shakespeare', 'character', 'id', id::text)
from shakespeare.character where name ilike 'a%' order by name limit 1;
