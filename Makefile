# Extension identity
EXTENSION = bundle
EXT_VERSION = 0.6.0
DATA = $(EXTENSION)--$(EXT_VERSION).sql
PG_CONFIG = pg_config

# Database configuration (user-configurable)
DB ?= $(EXTENSION)_dev
TEST_DB ?= tmp_bundle_test
AQUAMETA ?= ../..

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

# Testing with temporary database (default - safe)
test:
	@echo "==> Testing bundle with temporary database $(TEST_DB)..."
	@if psql -lqt | cut -d \| -f 1 | grep -qw $(TEST_DB); then \
		echo "ERROR: Temporary database $(TEST_DB) already exists. Please drop it or specify a different name."; \
		echo "       Usage: make test TEST_DB=different_name"; \
		exit 1; \
	fi
	@echo "==> Deploying full aquameta stack to $(TEST_DB)..."
	cd $(AQUAMETA) && make deploy DB=$(TEST_DB)
	@echo "==> Running bundle tests..."
	cd test && cat $(notdir $(TEST_FILES)) | psql -v ON_ERROR_STOP=1 $(TEST_DB)
	@echo "==> Tests completed successfully, cleaning up..."
	dropdb $(TEST_DB)
	@echo "==> Temporary database $(TEST_DB) dropped."

# Testing with temporary database (keep database for inspection)  
test-dirty:
	@echo "==> Testing bundle with temporary database $(TEST_DB) (dirty mode)..."
	@if psql -lqt | cut -d \| -f 1 | grep -qw $(TEST_DB); then \
		echo "ERROR: Temporary database $(TEST_DB) already exists. Please drop it or specify a different name."; \
		echo "       Usage: make test-dirty TEST_DB=different_name"; \
		exit 1; \
	fi
	@echo "==> Deploying full aquameta stack to $(TEST_DB)..."
	cd $(AQUAMETA) && make deploy DB=$(TEST_DB)
	@echo "==> Running bundle tests..."
	cd test && cat $(notdir $(TEST_FILES)) | psql -v ON_ERROR_STOP=1 $(TEST_DB)
	@echo "==> Tests completed. Database $(TEST_DB) preserved for inspection."

# Testing against existing database (requires DB parameter)
test-db:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter required. Usage: make test-db DB=existing_db"; \
		exit 1; \
	fi
	@echo "==> Running bundle tests against existing database $(DB)..."
	cd test && cat $(notdir $(TEST_FILES)) | psql -v ON_ERROR_STOP=1 $(DB)
	@echo "==> Tests completed."

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
	@echo "  test               - Create temp database, run tests, cleanup (default/safe)"
	@echo "  test-dirty         - Same as test but keep database for inspection"
	@echo "                       TEST_DB=name (default: tmp_bundle_test)"
	@echo "                       AQUAMETA=path (default: ../..)"
	@echo "  test-db DB=name    - Run tests against existing database"
	@echo "  deploy DB=name     - Deploy to specified database"
	@echo "  clean              - Clean generated files"

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Clean generated SQL files
clean:
	rm -f $(EXTENSION)--*.sql
