EXTENSION = bundle
EXTVERSION = 0.6.0
DATA = $(EXTENSION)--$(EXTVERSION).sql
PG_CONFIG = pg_config

$(EXTENSION)--$(EXTVERSION).sql: util.sql hash.sql rowset.sql repository.sql db.sql trackable.sql track.sql stage.sql commit.sql checkout.sql import-export.sql remote.sql merge.sql status.sql setup.sql extension.sql
	rm -f $@
	cat $^ > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
