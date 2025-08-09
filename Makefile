EXTENSION = bundle
EXTVERSION = 0.6.0
DATA = $(EXTENSION)--$(EXTVERSION).sql
PG_CONFIG = pg_config

# Build extension version (different content than standalone)
$(EXTENSION)--$(EXTVERSION)--extension.sql: begin_extension.sql util.sql hash.sql rowset.sql repository.sql db.sql trackable.sql track.sql stage.sql commit.sql checkout.sql import-export.sql remote.sql merge.sql status.sql setup.sql end_extension.sql
	rm -f $@
	cat $^ > $@

# Copy to the name PostgreSQL expects for install
$(EXTENSION)--$(EXTVERSION).sql: $(EXTENSION)--$(EXTVERSION)--extension.sql
	cp $< $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
