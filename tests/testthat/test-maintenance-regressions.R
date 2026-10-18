test_that("weak ETags cannot identify resumable bytes", {
  weak <- datapond:::identity_from_headers(list(etag = 'W/"same"'))
  expect_null(weak$etag)
  expect_null(datapond:::strong_validator(weak))
  # Even a date must not be substituted into If-Range when a weak ETag exists.
  dated <- datapond:::identity_from_headers(list(etag = 'W/"same"',
    `last-modified` = "Tue, 15 Sep 2026 00:00:00 GMT"))
  expect_null(datapond:::strong_validator(dated))
  tmp <- withr::local_tempdir()
  part <- file.path(tmp, "x.part")
  writeLines("old-prefix", part)
  jsonlite::write_json(weak, paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env()
  local_mocked_bindings(multi_download = function(urls, destfiles, resume, progress, httpheader) {
    calls$resume <- resume
    calls$headers <- httpheader
    calls$had_partial <- file.exists(destfiles)
    writeLines("new-file", destfiles)
    data.frame(success = TRUE, status_code = 200L,
      headers = I(list(c("HTTP/1.1 200 OK", 'etag: W/"same"', ""))))
  }, .package = "curl")
  datapond:::transfer("https://example.test/db", part, weak, quiet = TRUE)
  expect_false(calls$resume)
  expect_false(calls$had_partial)
  expect_length(calls$headers, 0L)
})

test_that("an ETag from another URL cannot mark a local copy current", {
  fixture <- local_datapond()
  db <- datapond:::dp_get_database("testdb")
  datapond:::write_sidecar(fixture$db, "testdb", "https://old.example/db", list(etag = "v1"))
  local_mocked_bindings(remote_identity = function(url) list(etag = "v1"))
  expect_match(datapond:::needs_update(db, fixture$db), "URL changed")
})

test_that("resource limits are applied before a database is attached", {
  local_datapond()
  spill <- file.path(withr::local_tempdir(), "spill")
  config <- list(memory_limit = "128MiB", threads = "1", temp_directory = spill,
                 max_temp_directory_size = "256MiB")
  con <- dp_connect("testdb", quiet = TRUE, config = config)
  on.exit(dp_disconnect(con))
  settings <- DBI::dbGetQuery(con, paste(
    "SELECT current_setting('memory_limit') AS memory,",
    "current_setting('threads') AS threads,",
    "current_setting('temp_directory') AS temp,",
    "current_setting('max_temp_directory_size') AS disk"))
  expect_equal(settings$memory, "128.0 MiB")
  expect_equal(settings$threads, 1)
  expect_equal(settings$temp, spill)
  expect_equal(settings$disk, "256.0 MiB")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM cases")$n, 3)
})

test_that("a session option can bound connections without changing call sites", {
  local_datapond()
  withr::local_options(datapond.duckdb_config = list(memory_limit = "128MiB", threads = "1"))
  con <- dp_connect("testdb", quiet = TRUE)
  on.exit(dp_disconnect(con))
  expect_equal(DBI::dbGetQuery(con, "SELECT current_setting('threads') AS n")$n, 1)
  expect_error(dp_connect("testdb", config = list("128MiB")), "named list")
})

test_that("a completed download survives an installation failure without retransferring", {
  tmp <- withr::local_tempdir()
  served <- make_fixture_db(file.path(tmp, "served.duckdb"))
  etag_file <- file.path(tmp, "etag.txt")
  writeLines("stable", etag_file)
  url <- local_file_server(served, etag_file)
  dest <- file.path(tmp, "download.duckdb")
  original <- datapond:::install_file
  local_mocked_bindings(install_file = function(...) stop("destination locked"))
  expect_error(datapond:::download_file(url, dest, quiet = TRUE), "destination locked")
  expect_true(file.exists(paste0(dest, ".part")))
  expect_true(file.exists(paste0(dest, ".part.meta")))
  # HEAD still verifies the revision. Any body download would fail this retry.
  local_mocked_bindings(install_file = original)
  local_mocked_bindings(multi_download = function(...) stop("unexpected retransmission"), .package = "curl")
  # A transiently unavailable identity probe must preserve the completed file.
  writeLines("unavailable", paste0(etag_file, ".mode"))
  expect_error(datapond:::download_file(url, dest, quiet = TRUE), "Could not verify")
  expect_identical(readBin(paste0(dest, ".part"), "raw", file.size(served)),
    readBin(served, "raw", file.size(served)))
  expect_true(file.exists(paste0(dest, ".part.meta")))
  writeLines("range", paste0(etag_file, ".mode"))
  datapond:::download_file(url, dest, quiet = TRUE)
  expect_identical(readBin(dest, "raw", file.size(dest)), readBin(served, "raw", file.size(served)))
  expect_false(file.exists(paste0(dest, ".part.meta")))
})

test_that("a partial file from another URL is restarted despite an equal ETag", {
  tmp <- withr::local_tempdir()
  part <- file.path(tmp, "x.part")
  writeLines("old", part)
  jsonlite::write_json(list(etag = "v1", url = "https://old.example/db"), paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env()
  local_mocked_bindings(multi_download = function(urls, destfiles, resume, progress, httpheader) {
    calls$had_partial <- file.exists(destfiles)
    calls$headers <- httpheader
    writeLines("new", destfiles)
    data.frame(success = TRUE, status_code = 200L,
      headers = I(list(c("HTTP/1.1 200 OK", 'etag: "v1"', ""))))
  }, .package = "curl")
  datapond:::transfer("https://new.example/db", part, list(etag = "v1"), quiet = TRUE)
  expect_false(calls$had_partial)
  expect_length(calls$headers, 0L)
})

test_that("a weak GET tag cannot inherit a strong HEAD tag", {
  part <- file.path(withr::local_tempdir(), "x.part")
  calls <- new.env(); calls$n <- 0L
  local_mocked_bindings(multi_download = function(urls, destfiles, resume, progress, httpheader) {
    calls$n <- calls$n + 1L
    calls$resume <- resume
    writeLines("new-file", destfiles)
    data.frame(success = TRUE, status_code = 200L,
      headers = I(list(c("HTTP/1.1 200 OK", 'etag: W/"weak"', ""))))
  }, .package = "curl")
  result <- datapond:::transfer("https://example.test/db", part, list(etag = "strong"), quiet = TRUE)
  expect_equal(calls$n, 1L)
  expect_null(result$identity$etag)
  expect_equal(result$identity$weak_etag, 'W/"weak"')
  saved <- jsonlite::read_json(paste0(part, ".meta"))
  expect_null(datapond:::strong_validator(saved))
})

test_that("validation failure does not poison a later download with the same revision", {
  tmp <- withr::local_tempdir()
  valid <- fixture_bytes(tmp, 1)
  bad <- valid; bad[1:16] <- as.raw(rep(0L, 16))
  served <- file.path(tmp, "served.bin"); writeBin(bad, served)
  etag_file <- file.path(tmp, "etag.txt"); writeLines("stable", etag_file)
  url <- local_file_server(served, etag_file)
  dest <- file.path(tmp, "download.duckdb")
  previous <- fixture_bytes(tmp, 2); writeBin(previous, dest)
  expect_error(datapond:::download_file(url, dest, quiet = TRUE), "not a readable DuckDB")
  expect_identical(readBin(dest, "raw", file.size(dest)), previous)
  expect_false(file.exists(paste0(dest, ".part.meta")))
  # Same tag and length: retry must fetch fresh bytes after validation failure.
  writeBin(valid, served)
  datapond:::download_file(url, dest, quiet = TRUE)
  expect_identical(readBin(dest, "raw", file.size(dest)), valid)
})

test_that("integer and logical DuckDB settings work before attachment", {
  local_datapond()
  con <- dp_connect("testdb", quiet = TRUE, config = list(
    threads = 1L, memory_limit = "128MiB", preserve_insertion_order = FALSE))
  on.exit(dp_disconnect(con))
  settings <- DBI::dbGetQuery(con, paste(
    "SELECT current_setting('threads') AS threads,",
    "current_setting('preserve_insertion_order') AS progress"))
  expect_equal(settings$threads, 1)
  expect_false(settings$progress)
  expect_error(dp_connect("testdb", config = list(threads = c(1L, 2L))), "scalar")
  expect_error(dp_connect("testdb", config = list(threads = NA_integer_)), "scalar")
})

test_that("an empty quoted ETag remains a strong validator", {
  identity <- datapond:::identity_from_headers(list(etag = '""',
    `last-modified` = "Tue, 15 Sep 2026 00:00:00 GMT"))
  expect_identical(datapond:::strong_validator(identity), "")
  part <- file.path(withr::local_tempdir(), "x.part")
  url <- "https://example.test/db"
  writeLines("old-prefix", part)
  jsonlite::write_json(c(identity, list(url = url)), paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env()
  local_mocked_bindings(multi_download = function(urls, destfiles, resume, progress, httpheader) {
    calls$headers <- httpheader
    writeLines("new-file", destfiles)
    data.frame(success = TRUE, status_code = 206L,
      headers = I(list(c("HTTP/1.1 206 Partial Content", 'etag: ""', ""))))
  }, .package = "curl")
  datapond:::transfer(url, part, identity, quiet = TRUE)
  expect_identical(calls$headers, 'If-Range: ""')
})

test_that("different weak ETags cannot be hidden by an unchanged date", {
  fixture <- local_datapond()
  db <- datapond:::dp_get_database("testdb")
  date <- "Tue, 15 Sep 2026 00:00:00 GMT"
  datapond:::write_sidecar(fixture$db, "testdb", db$attach_url,
    list(weak_etag = 'W/"v1"', last_modified = date))
  local_mocked_bindings(remote_identity = function(url)
    list(weak_etag = 'W/"v2"', last_modified = date))
  expect_match(datapond:::needs_update(db, fixture$db), "remote file changed")
})

test_that("a resumed GET with a weak validator restarts without a range", {
  part <- file.path(withr::local_tempdir(), "x.part")
  url <- "https://example.test/db"
  writeLines("old-prefix", part)
  jsonlite::write_json(list(etag = "strong", url = url), paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env(); calls$headers <- list()
  local_mocked_bindings(multi_download = function(urls, destfiles, resume, progress, httpheader) {
    calls$headers[[length(calls$headers) + 1L]] <- httpheader
    writeLines("new-file", destfiles)
    data.frame(success = TRUE, status_code = if (length(httpheader)) 206L else 200L,
      headers = I(list(c(if (length(httpheader)) "HTTP/1.1 206 Partial Content" else "HTTP/1.1 200 OK", 'etag: W/"weak"', ""))))
  }, .package = "curl")
  result <- datapond:::transfer(url, part, list(etag = "strong"), quiet = TRUE)
  expect_length(calls$headers, 2L)
  expect_identical(calls$headers[[1]], 'If-Range: "strong"')
  expect_length(calls$headers[[2]], 0L)
  expect_null(result$identity$etag)
})

test_that("a fresh HTTP response cannot inherit stale HEAD identity", {
  part <- file.path(withr::local_tempdir(), "new.part")
  local_mocked_bindings(multi_download = function(urls, destfiles, ...) {
    writeBin(charToRaw("new"), destfiles)
    data.frame(success = TRUE, status_code = 200L, headers = I(list(c(
      "HTTP/1.1 200 OK", "content-length: 3",
      "last-modified: Wed, 16 Sep 2026 00:00:00 GMT", ""))))
  }, .package = "curl")
  result <- datapond:::transfer("https://example.test/db", part,
    list(etag = "old", size = 5), quiet = TRUE)
  expect_null(result$identity$etag)
  expect_equal(result$identity$size, 3)
  saved <- jsonlite::read_json(paste0(part, ".meta"))
  expect_null(saved$etag)
  expect_equal(saved$last_modified, "Wed, 16 Sep 2026 00:00:00 GMT")
})

test_that("a change in ETag strength cannot hide behind an unchanged date", {
  fixture <- local_datapond()
  db <- datapond:::dp_get_database("testdb")
  date <- "Tue, 15 Sep 2026 00:00:00 GMT"
  for (tags in list(list(list(etag = "v1"), list(weak_etag = 'W/"v2"')),
                   list(list(weak_etag = 'W/"v1"'), list(etag = "v2")),
                   list(list(etag = "v1"), list(weak_etag = 'W/"v1"')))) {
    datapond:::write_sidecar(fixture$db, "testdb", db$attach_url,
      c(tags[[1]], list(last_modified = date)))
    remote <- c(tags[[2]], list(last_modified = date))
    local_mocked_bindings(remote_identity = function(url) remote)
    expect_match(datapond:::needs_update(db, fixture$db), "remote file changed")
  }
})

test_that("an incomplete transfer reports its size and clears its completion marker", {
  dest <- file.path(withr::local_tempdir(), "db.duckdb")
  writeLines("previous", dest)
  local_mocked_bindings(remote_identity = function(url) list(),
    transfer = function(url, part, ...) {
      writeBin(charToRaw("bad"), part)
      jsonlite::write_json(list(complete = TRUE), paste0(part, ".meta"))
      list(identity = list(size = 5))
    })
  expect_error(datapond:::download_file("https://example.test/db", dest, quiet = TRUE),
    "Download incomplete: 3 of 5 bytes", fixed = TRUE)
  expect_false(file.exists(paste0(dest, ".part")))
  expect_false(file.exists(paste0(dest, ".part.meta")))
  expect_identical(readLines(dest), "previous")
})


test_that("a date-bound resume can adopt a strong GET tag without restarting", {
  part <- file.path(withr::local_tempdir(), "db.part")
  url <- "https://example.test/db"
  date <- "Tue, 15 Sep 2026 00:00:00 GMT"
  writeBin(charToRaw("a"), part)
  jsonlite::write_json(list(url = url, last_modified = date), paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env(); calls$n <- 0L
  local_mocked_bindings(multi_download = function(urls, destfiles, httpheader, ...) {
    calls$n <- calls$n + 1L; calls$header <- httpheader
    writeBin(charToRaw("abc"), destfiles)
    data.frame(success = TRUE, status_code = 206L, headers = I(list(c(
      "HTTP/1.1 206 Partial Content", 'etag: "abc"', paste0("last-modified: ", date),
      "content-range: bytes 1-2/3", "content-length: 2", ""))))
  }, .package = "curl")
  result <- datapond:::transfer(url, part, list(last_modified = date), quiet = TRUE)
  expect_equal(calls$n, 1L)
  expect_identical(calls$header, paste0("If-Range: ", date))
  expect_identical(result$identity$etag, "abc")
  expect_equal(result$identity$size, 3)
})

test_that("interrupted resumes retain their bytes and identity for the next call", {
  tmp <- withr::local_tempdir()
  url <- "https://example.test/db"
  for (status in c(206L, NA_integer_, 503L)) {
    part <- file.path(tmp, paste0("partial-", status))
    writeBin(charToRaw("prefix"), part)
    jsonlite::write_json(list(etag = "v1", url = url), paste0(part, ".meta"), auto_unbox = TRUE)
    calls <- new.env(); calls$n <- 0L
    local_mocked_bindings(multi_download = function(...) {
      calls$n <- calls$n + 1L
      data.frame(success = FALSE, status_code = status,
        headers = I(list(c("HTTP/1.1 206 Partial Content", 'etag: "v1"', ""))))
    }, .package = "curl")
    expect_error(datapond:::transfer(url, part, list(etag = "v1"), quiet = TRUE), "Download failed")
    expect_true(file.exists(part))
    expect_identical(readBin(part, "raw", 6L), charToRaw("prefix"))
    expect_true(file.exists(paste0(part, ".meta")))
    expect_equal(calls$n, 1L)
  }
})

test_that("an unsatisfiable resumed range restarts once from the full response", {
  part <- file.path(withr::local_tempdir(), "db.part")
  url <- "https://example.test/db"
  writeBin(charToRaw("too-long"), part)
  jsonlite::write_json(list(etag = "v1", url = url), paste0(part, ".meta"), auto_unbox = TRUE)
  calls <- new.env(); calls$n <- 0L
  local_mocked_bindings(remote_identity = function(url) list(etag = "v1"))
  local_mocked_bindings(multi_download = function(urls, destfiles, ...) {
    calls$n <- calls$n + 1L
    if (calls$n == 1L) return(data.frame(success = FALSE, status_code = 416L))
    writeBin(charToRaw("new"), destfiles)
    data.frame(success = TRUE, status_code = 200L,
      headers = I(list(c("HTTP/1.1 200 OK", 'etag: "v1"', "content-length: 3", ""))))
  }, .package = "curl")
  datapond:::transfer(url, part, list(etag = "v1"), quiet = TRUE)
  expect_equal(calls$n, 2L)
  expect_identical(readBin(part, "raw", 3L), charToRaw("new"))
})
