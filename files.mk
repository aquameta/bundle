# Centralized SQL file order - single source of truth
# This file is included by both Makefile and any scripts that need the file list

SQL_FILES_STANDALONE = _begin.sql \
    util.sql \
    hash.sql \
    rowset.sql \
    repository.sql \
    db.sql \
    trackable.sql \
    track.sql \
    stage.sql \
    commit.sql \
    checkout.sql \
    import-export.sql \
    remote.sql \
    merge.sql \
    status.sql \
    setup.sql \
    _end.sql

SQL_FILES_EXTENSION = _begin_extension.sql \
    util.sql \
    hash.sql \
    rowset.sql \
    repository.sql \
    db.sql \
    trackable.sql \
    track.sql \
    stage.sql \
    commit.sql \
    checkout.sql \
    import-export.sql \
    remote.sql \
    merge.sql \
    status.sql \
    setup.sql \
    _end_extension.sql

TEST_FILES = test/_begin.sql \
    test/util.sql \
    test/hash.sql \
    test/rowset.sql \
    test/repository.sql \
    test/db.sql \
    test/trackable.sql \
    test/track.sql \
    test/stage.sql \
    test/commit.sql \
    test/checkout.sql \
    test/remote.sql \
    test/merge.sql \
    test/status.sql # \
#    test/meta.sql \
#    test/meta/schema.sql \
#    test/meta/table.sql \
#    test/meta/column.sql \
#    test/_end.sql
