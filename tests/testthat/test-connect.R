test_that("attach_sql quotes identifiers and string literals", {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  sql <- datapond:::attach_sql(con, "https://x/y.duckdb", "cms-medicare")
  expect_equal(sql, "ATTACH 'https://x/y.duckdb' AS \"cms-medicare\" (READ_ONLY)")
  sql <- datapond:::attach_sql(con, "/tmp/it's.duckdb", "we\"ird")
  expect_equal(sql, "ATTACH '/tmp/it''s.duckdb' AS \"we\"\"ird\" (READ_ONLY)")
})

test_that("a single id is attached and made the default catalog", {
  local_datapond()
  expect_message(con <- dp_connect("testdb"), "Connected. 2 tables available")
  on.exit(dp_disconnect(con))
  expect_s4_class(con, "duckdb_connection")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM cases")$n, 3)
})

test_that("hyphenated ids work with USE and qualified references", {
  local_datapond()
  con <- dp_connect("test-hyphen", quiet = TRUE)
  on.exit(dp_disconnect(con))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM cases")$n, 3)
  expect_equal(DBI::dbGetQuery(con, 'SELECT count(*) AS n FROM "test-hyphen".lu_nationality')$n, 2)
})

test_that("multiple ids are attached without USE", {
  local_datapond()
  expect_message(con <- dp_connect(c("testdb", "test-hyphen"), quiet = FALSE),
                 "across 2 databases")
  on.exit(dp_disconnect(con))
  expect_error(DBI::dbGetQuery(con, "SELECT count(*) FROM cases"))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM testdb.cases")$n, 3)
})

test_that("local = TRUE requires a downloaded file", {
  local_datapond()
  expect_error(dp_connect("testdb", local = TRUE), "dp_download\\('testdb'\\)")
  dir.create(dp_data_dir(), recursive = TRUE)
  file.copy(dp_info("testdb")$attach_url, dp_local_path("testdb"))
  con <- dp_connect("testdb", local = TRUE, quiet = TRUE)
  on.exit(dp_disconnect(con))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM cases")$n, 3)
})
