# Extension identity
EXTENSION = bundle

# Include centralized file list (defines SQL_FILES_STANDALONE, SQL_FILES_EXTENSION, TEST_FILES)
include files.mk

# Include common build logic
include ../common.mk
