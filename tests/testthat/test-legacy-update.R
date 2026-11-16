test_that("registry dates cannot verify legacy copies without recorded identity", {
  fixture <- local_datapond()
  local <- dp_local_path("testdb")
  dir.create(dirname(local), recursive = TRUE)
  file.copy(fixture$db, local)
  db <- datapond:::dp_get_database("testdb")
  for (date in c("2026-01-01 08:00:00", "2026-10-18 00:00:00", "2099-01-01 00:00:00")) {
    Sys.setFileTime(local, as.POSIXct(date, tz = "UTC"))
    expect_type(datapond:::needs_update(db, local), "character")
  }
  for (metadata in c("invalid JSON", "true", "[]", "{}", '{"etag":true}',
                     '{"url":["one","two"]}', '{"local_size":[1,2]}')) {
    writeLines(metadata, datapond:::sidecar_path(local))
    expect_type(datapond:::needs_update(db, local), "character")
  }
})

test_that("an update replaces stale legacy bytes despite a later local timestamp", {
  fixture <- local_datapond()
  local <- dp_local_path("testdb")
  dir.create(dirname(local), recursive = TRUE)
  file.copy(fixture$db, local)
  Sys.setFileTime(local, as.POSIXct("2026-10-18 00:00:00", tz = "UTC"))
  upstream <- DBI::dbConnect(duckdb::duckdb(), dbdir = fixture$db)
  DBI::dbExecute(upstream, "UPDATE cases SET NAT='CA' WHERE IDNCASE=1")
  DBI::dbDisconnect(upstream, shutdown = TRUE)
  # Real file:// transfer, validation and installation; no namespace mocks.
  registry <- jsonlite::read_json(fixture$registry, simplifyVector = FALSE)
  registry$databases[[1]]$download_url <- paste0("file://", fixture$db)
  registry$databases[[1]]$updated <- "2026-10-17"
  jsonlite::write_json(registry, fixture$registry, auto_unbox = TRUE)
  dp_registry(refresh = TRUE)
  dp_update("testdb", quiet = TRUE)
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = local, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_equal(DBI::dbGetQuery(con, "SELECT NAT FROM cases WHERE IDNCASE=1")$NAT, "CA")
  expect_true(file.exists(datapond:::sidecar_path(local)))
})
