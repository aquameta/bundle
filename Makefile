# Extension identity
EXTENSION = bundle
EXT_VERSION = 0.6.0
DATA = $(EXTENSION)--$(EXT_VERSION).sql
PG_CONFIG = pg_config

# Database configuration (user-configurable)
DB ?= $(EXTENSION)_dev
TEST_DB ?= tmp_$(EXTENSION)_test
AQUAMETA ?= ../..

# Global psql flags (for debugging, remote connections, etc.)
# Examples: 
#   PSQL_FLAGS="-a -e" make test           # Show commands (debugging)
#   PSQL_FLAGS="-h myhost -U user" make deploy  # Remote connection  
#   PSQL_FLAGS="-h db.supabase.co -U postgres" make test  # Supabase
PSQL_FLAGS ?=

# Include centralized file list
include files.mk

# Declare phony targets (commands, not files)
.PHONY: extension standalone all test test-all test-dirty test-db deploy clean help

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

# Testing with temporary database (default - fail fast)
test:
	@echo "==> Testing $(EXTENSION) with temporary database $(TEST_DB) (fail fast)..."
	@if psql -lqt | cut -d \| -f 1 | grep -qw $(TEST_DB); then \
		echo "ERROR: Temporary database $(TEST_DB) already exists. Please drop it or specify a different name."; \
		echo "       Usage: make test TEST_DB=different_name"; \
		exit 1; \
	fi
	@echo "==> Deploying full aquameta stack to $(TEST_DB)..."
	cd $(AQUAMETA) && make deploy DB=$(TEST_DB)
	@echo "==> Running $(EXTENSION) tests (stopping on first error)..."
	@if cd test && cat $(notdir $(TEST_FILES)) | psql $(PSQL_FLAGS) -v ON_ERROR_STOP=1 $(TEST_DB); then \
		echo "==> Tests completed successfully, cleaning up..."; \
	else \
		echo "==> Tests failed, cleaning up..."; \
	fi
	@dropdb $(TEST_DB)
	@echo "==> Temporary database $(TEST_DB) dropped."

# Testing with temporary database (run all tests regardless of failures)
test-all:
	@echo "==> Testing $(EXTENSION) with temporary database $(TEST_DB) (run all)..."
	@if psql -lqt | cut -d \| -f 1 | grep -qw $(TEST_DB); then \
		echo "ERROR: Temporary database $(TEST_DB) already exists. Please drop it or specify a different name."; \
		echo "       Usage: make test-all TEST_DB=different_name"; \
		exit 1; \
	fi
	@echo "==> Deploying full aquameta stack to $(TEST_DB)..."
	cd $(AQUAMETA) && make deploy DB=$(TEST_DB)
	@echo "==> Running $(EXTENSION) tests (continuing on errors)..."
	@cd test && cat $(notdir $(TEST_FILES)) | psql $(PSQL_FLAGS) $(TEST_DB) || true
	@echo "==> Tests completed, cleaning up..."
	@dropdb $(TEST_DB)
	@echo "==> Temporary database $(TEST_DB) dropped."

# Testing with temporary database (keep database for inspection)  
test-dirty:
	@echo "==> Testing $(EXTENSION) with temporary database $(TEST_DB) (dirty mode)..."
	@if psql -lqt | cut -d \| -f 1 | grep -qw $(TEST_DB); then \
		echo "ERROR: Temporary database $(TEST_DB) already exists. Please drop it or specify a different name."; \
		echo "       Usage: make test-dirty TEST_DB=different_name"; \
		exit 1; \
	fi
	@echo "==> Deploying full aquameta stack to $(TEST_DB)..."
	cd $(AQUAMETA) && make deploy DB=$(TEST_DB)
	@echo "==> Running $(EXTENSION) tests..."
	cd test && cat $(notdir $(TEST_FILES)) | psql $(PSQL_FLAGS) -v ON_ERROR_STOP=1 $(TEST_DB)
	@echo "==> Tests completed. Database $(TEST_DB) preserved for inspection."

# Testing against existing database (requires DB parameter)
test-db:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter required. Usage: make test-db DB=existing_db"; \
		exit 1; \
	fi
	@echo "==> Running $(EXTENSION) tests against existing database $(DB)..."
	cd test && cat $(notdir $(TEST_FILES)) | psql $(PSQL_FLAGS) -v ON_ERROR_STOP=1 $(DB)
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
	@echo "Make targets:"
	@echo "  extension          - Build extension (default)"
	@echo "  install            - Install as PostgreSQL extension"
	@echo "  standalone         - Build standalone .sql file (./$(EXTENSION)--$(EXT_VERSION)--standalone.sql)"
	@echo "  all                - Build both extension and standalone"
	@echo ""
	@echo "Testing:"
	@echo "  test               - Create temp database, run tests, cleanup (stops on first error)"
	@echo "  test-all           - Same as test but continues on errors (shows all failures)"
	@echo "  test-dirty         - Same as test but keep database for inspection"
	@echo "  test-db DB=name    - Run tests against existing database"
	@echo "  Flags:"
	@echo "      TEST_DB=name       - Temporary database name (default: tmp_$(EXTENSION)_test)"
	@echo "      AQUAMETA=path      - Path to Aquameta root for \`make deploy\` (default: ../..)"
	@echo ""
	@echo "Deploy:"
	@echo "  deploy DB=name     - Deploy to specified database"
	@echo "  clean              - Clean generated files"
	@echo ""
	@echo ""
	@echo "Global Configuration:"
	@echo "  PSQL_FLAGS='flags' - Additional psql flags for all psql operations"
	@echo "                       Examples:"
	@echo "                         PSQL_FLAGS='-a -e' make test     # Show commands"
	@echo "                         PSQL_FLAGS='-h host -U user' make deploy  # Remote"

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Clean generated SQL files
clean:
	rm -f $(EXTENSION)--*.sql
