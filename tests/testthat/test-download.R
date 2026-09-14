fake_download <- function(url, dest, quiet = FALSE, resume = TRUE) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(url, dest, overwrite = TRUE)
  invisible(dest)
}

test_that("dp_download resolves the destination and saves <id>.duckdb", {
  local_datapond()
  local_mocked_bindings(download_file = fake_download)
  expect_message(path <- dp_download("testdb"), "Saved to")
  expect_equal(path, dp_local_path("testdb"))
  expect_true(file.exists(path))

  dir <- withr::local_tempdir()
  path2 <- dp_download("test-hyphen", path = dir, quiet = TRUE)
  expect_equal(path2, file.path(dir, "test-hyphen.duckdb"))
})

test_that("dp_update downloads when missing, skips when current, refreshes when stale", {
  local_datapond()
  local_mocked_bindings(download_file = fake_download)
  expect_message(dp_update("testdb"), "No local copy")
  expect_message(dp_update("testdb"), "already up to date")
  Sys.setFileTime(dp_local_path("testdb"), as.POSIXct("2020-01-01", tz = "UTC"))
  expect_message(dp_update("testdb"), "Updating testdb")
})

test_that("a partial file never masquerades as a database", {
  local_datapond()
  expect_error(datapond:::download_file("file:///nonexistent/x.duckdb",
                                        file.path(withr::local_tempdir(), "x.duckdb"), quiet = TRUE))
})
