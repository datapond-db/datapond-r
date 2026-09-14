test_that("a real database can be attached remotely", {
  skip_on_cran()
  skip_if_offline("huggingface.co")
  withr::local_options(datapond.cache_dir = withr::local_tempdir(),
                       datapond.registry_url = NULL)
  expect_true("dol-visas" %in% dp_list())
  con <- dp_connect("dol-visas", quiet = TRUE)
  on.exit(dp_disconnect(con))
  n <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM lca")$n
  expect_gt(n, 1e6)
  expect_gt(nrow(dp_describe(con)), 0)
})
