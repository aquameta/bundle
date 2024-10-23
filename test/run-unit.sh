cat init.sql init-unit.sql repository.sql db.sql ignore.sql track.sql stage.sql commit.sql checkout.sql end.sql | psql -v ON_ERROR_STOP=1 -b delta
