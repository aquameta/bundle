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
.PHONY: build build-standalone build-extension dev test db-create db-drop db-reset clean help

# Build targets - default is extension
build-extension: $(DATA)

build-standalone: $(EXTENSION)--$(EXT_VERSION)--standalone.sql

build: build-standalone build-extension

$(EXTENSION)--$(EXT_VERSION)--standalone.sql: $(SQL_FILES_STANDALONE)
	rm -f $@
	cat $^ > $@

$(DATA): $(SQL_FILES_EXTENSION)
	rm -f $@
	cat $^ > $@

# Database management
db-create:
	createdb $(DB)

db-drop:
	dropdb --if-exists $(DB)

db-reset: db-drop db-create

# Development workflow
install-dev: build-standalone db-create
	cat $(EXTENSION)--$(EXT_VERSION)--standalone.sql | psql $(DB)

dev: install-dev test

# Testing
test: build-standalone
	dropdb --if-exists $(DB)_test
	createdb $(DB)_test
	cat $(EXTENSION)--$(EXT_VERSION)--standalone.sql | psql $(DB)_test
	cat $(TEST_FILES) | psql -v ON_ERROR_STOP=1 -b $(DB)_test

# Help target
help:
	@echo "Available targets:"
	@echo "  build              - Build both standalone and extension versions"
	@echo "  build-standalone   - Build standalone version"
	@echo "  build-extension    - Build extension version"
	@echo "  install            - Install as PostgreSQL extension"
	@echo "  install-dev        - Install to development database ($(DB))"
	@echo "  dev                - Full development cycle (install + test)"
	@echo "  test               - Run all tests ($(DB)_test)"
	@echo "  db-create          - Create development database"
	@echo "  db-drop            - Drop development database"
	@echo "  db-reset           - Reset development database"
	@echo "  clean              - Clean generated files"
	@echo ""
	@echo "Database configuration:"
	@echo "  DB=$(DB) (override with DB=mydb)"

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Clean generated SQL files
clean:
	rm -f $(EXTENSION)--*.sql