# Extension identity
EXTENSION = bundle
EXT_VERSION = 0.6.0
DATA = $(EXTENSION)--$(EXT_VERSION).sql
PG_CONFIG = pg_config

# Database configuration (user-configurable)
DB ?= $(EXTENSION)_dev

# Include centralized file list
include files.mk

# Declare phony targets (commands, not files)
.PHONY: extension standalone all test deploy clean help

# Build targets - default is extension
extension: $(DATA)

standalone: $(EXTENSION)--$(EXT_VERSION)--standalone.sql

all: standalone extension

$(EXTENSION)--$(EXT_VERSION)--standalone.sql: $(SQL_FILES_STANDALONE)
	rm -f $@
	cat $^ > $@

$(DATA): $(SQL_FILES_EXTENSION)
	rm -f $@
	cat $^ > $@

# Testing (requires DB parameter)
test: standalone
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter required. Usage: make test DB=mydb"; \
		exit 1; \
	fi
	dropdb --if-exists $(DB)_test
	createdb $(DB)_test
	cat $(EXTENSION)--$(EXT_VERSION)--standalone.sql | psql $(DB)_test
	cat $(TEST_FILES) | psql -v ON_ERROR_STOP=1 -b $(DB)_test

# Deploy to database (requires DB parameter)
deploy: standalone
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter required. Usage: make deploy DB=mydb"; \
		exit 1; \
	fi
	@echo "==> Deploying $(EXTENSION) to database $(DB)..."
	createdb $(DB) || echo "Database $(DB) already exists"
	cat $(EXTENSION)--$(EXT_VERSION)--standalone.sql | psql $(DB)

# Help target
help:
	@echo "Available targets:"
	@echo "  extension          - Build extension (default)"
	@echo "  standalone         - Build standalone"
	@echo "  all                - Build both extension and standalone"
	@echo "  install            - Install as PostgreSQL extension"
	@echo "  test DB=name       - Run all tests on specified database"
	@echo "  deploy DB=name     - Deploy to specified database"
	@echo "  clean              - Clean generated files"

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Clean generated SQL files
clean:
	rm -f $(EXTENSION)--*.sql
