test_that("registry is read from the configured source and cached", {
  fx <- local_datapond()
  expect_equal(dp_list(), c("testdb", "test-hyphen"))
  expect_true(file.exists(file.path(dp_cache_dir(), "registry.json")))

  # A fresh cache is served without touching the source again.
  unlink(fx$registry)
  expect_equal(dp_list(), c("testdb", "test-hyphen"))
})

test_that("a stale cache is used when the source is unreachable", {
  fx <- local_datapond()
  dp_list()
  cache <- file.path(dp_cache_dir(), "registry.json")
  Sys.setFileTime(cache, Sys.time() - 7200)
  unlink(fx$registry)
  expect_warning(ids <- dp_list(), "cached copy")
  expect_equal(ids, c("testdb", "test-hyphen"))
})

test_that("unknown ids give a helpful error", {
  local_datapond()
  expect_error(dp_info("nope"), "not found.*Available: testdb, test-hyphen")
})

test_that("dp_info prints and dp_databases tabulates", {
  local_datapond()
  info <- dp_info("testdb")
  expect_s3_class(info, "datapond_db")
  expect_output(print(info), "Test DB")
  dbs <- dp_databases()
  expect_equal(nrow(dbs), 2L)
  expect_equal(dbs$id, c("testdb", "test-hyphen"))
  expect_equal(dbs$rows, c(5, 5))
})
