EXTENSION = pg_ditty
EXTVERSION = 0.1.0
DATA = $(EXTENSION)--$(EXTVERSION).sql
PG_CONFIG = pg_config

$(EXTENSION)--$(EXTVERSION).sql: util.sql hash.sql rowset.sql repository.sql db.sql trackable.sql track.sql stage.sql commit.sql checkout.sql remote.sql merge.sql status.sql setup.sql
	rm -f $@
	cat $^ > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
