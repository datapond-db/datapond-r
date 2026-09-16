fake_download <- function(url, dest, quiet = FALSE, resume = TRUE, id = NULL) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(url, dest, overwrite = TRUE)
  datapond:::write_sidecar(dest, id %||% "x", url, list(etag = "v1", size = file.size(dest)))
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
  # a not-yet-existing directory (trailing slash or no .duckdb suffix) is created
  newdir <- file.path(dir, "fresh")
  path3 <- dp_download("testdb", path = paste0(newdir, "/"), quiet = TRUE)
  expect_equal(path3, file.path(newdir, "testdb.duckdb"))
  expect_true(file.exists(path3))
})

test_that("dp_update compares the remote identity, not the modification time", {
  local_datapond()
  local_mocked_bindings(download_file = fake_download)
  expect_message(dp_update("testdb"), "No local copy")
  local_mocked_bindings(remote_identity = function(url) list(etag = "v1"))
  expect_message(dp_update("testdb"), "already up to date")
  # an old mtime is irrelevant while the ETag matches
  Sys.setFileTime(dp_local_path("testdb"), as.POSIXct("2020-01-01", tz = "UTC"))
  expect_message(dp_update("testdb"), "already up to date")
  local_mocked_bindings(remote_identity = function(url) list(etag = "v2"))
  expect_message(dp_update("testdb"), "remote file changed")
})

test_that("a copy without a sidecar is not trusted on the registry's release day", {
  local_datapond()
  local_mocked_bindings(download_file = fake_download, remote_identity = function(url) list())
  dp_download("testdb", quiet = TRUE)
  unlink(datapond:::sidecar_path(dp_local_path("testdb")))
  db <- datapond:::dp_get_database("testdb")
  local <- dp_local_path("testdb")
  Sys.setFileTime(local, as.POSIXct(paste(db$updated, "08:00:00"), tz = "UTC"))
  expect_match(datapond:::needs_update(db, local), "newer release|no version")
  Sys.setFileTime(local, as.POSIXct(db$updated, tz = "UTC") + 2 * 86400)
  expect_null(datapond:::needs_update(db, local))
})

test_that("a resume restarts when the remote revision changed", {
  tmp <- withr::local_tempdir()
  part <- file.path(tmp, "x.duckdb.part")
  calls <- list()
  local_mocked_bindings(
    multi_download = function(urls, destfiles, resume = TRUE, progress = TRUE, ...) {
      existed <- file.exists(destfiles)
      calls[[length(calls) + 1]] <<- list(existed = existed, resume = resume)
      cat(if (existed) "version-two" else "NEW-version-two", file = destfiles, append = existed)
      data.frame(success = TRUE, status_code = 200L)
    },
    .package = "curl")
  writeLines("OLD-", part, sep = "")
  writeLines('{"etag":"old"}', paste0(part, ".meta"))
  datapond:::transfer("http://example/x", part, list(etag = "new"), quiet = TRUE)
  expect_equal(readLines(part, warn = FALSE), "NEW-version-two")
  expect_false(calls[[1]]$existed)
  # same revision: the partial file is kept and resumed
  writeLines("OLD-", part, sep = "")
  writeLines('{"etag":"new"}', paste0(part, ".meta"))
  datapond:::transfer("http://example/x", part, list(etag = "new"), quiet = TRUE)
  expect_equal(readLines(part, warn = FALSE), "OLD-version-two")
  expect_true(calls[[2]]$existed)
})

test_that("a failed replacement errors and keeps the existing file", {
  tmp <- withr::local_tempdir()
  dest <- file.path(tmp, "x.duckdb"); part <- paste0(dest, ".part")
  writeLines("good", dest); writeLines("new", part)
  local_mocked_bindings(file.rename = function(from, to) FALSE, file.copy = function(...) FALSE, .package = "base")
  expect_error(datapond:::install_file(part, dest), "Could not replace")
  expect_equal(readLines(dest), "good")
})

test_that("a partial file never masquerades as a database", {
  local_datapond()
  expect_error(datapond:::download_file("file:///nonexistent/x.duckdb",
                                        file.path(withr::local_tempdir(), "x.duckdb"), quiet = TRUE))
  tmp <- withr::local_tempdir()
  bad <- file.path(tmp, "bad.duckdb"); writeLines("not a database", bad)
  expect_error(datapond:::validate_database(bad), "not a readable DuckDB")
})
