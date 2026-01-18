# SQL files in order
# Reorganized structure:
#   - types.sql: All type definitions consolidated
#   - core.sql: Renamed from repository.sql for clarity
#   - stage.sql: Merged db.sql + stage.sql + db2.sql for cohesion
#   - checkout.sql: Now includes undelete/revert operations
#   - track.sql: Consolidated all tracking operations
SQL_FILES = _begin.sql \
    types.sql \
    util.sql \
    hash.sql \
    rowset.sql \
    core.sql \
    trackable.sql \
    track.sql \
    stage.sql \
    commit.sql \
    checkout.sql \
    stash.sql \
    import-export.sql \
    remote.sql \
    merge.sql \
    status.sql \
    history.sql \
    setup.sql \
    _end.sql

TEST_FILES = test/_begin.sql \
    test/util.sql \
    test/hash.sql \
    test/rowset.sql \
    test/core.sql \
    test/trackable.sql \
    test/track.sql \
    test/stage.sql \
    test/commit.sql \
    test/checkout.sql \
    test/remote.sql \
    test/merge.sql \
    test/status.sql
