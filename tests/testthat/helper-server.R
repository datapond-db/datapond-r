# A real loopback HTTP file server (httpuv in a background callr process) with ETag,
# HEAD, Range and If-Range semantics, so download tests exercise curl's actual
# behaviour: header vectors, HTTP 206 resumes, and a 200 answer to a stale If-Range.
# The served file and its ETag are read from disk on every request, so a test can
# change the "revision" between two requests.
local_file_server <- function(file, etag_file, env = parent.frame()) {
  testthat::skip_if_not_installed("httpuv")
  testthat::skip_if_not_installed("callr")
  port <- httpuv::randomPort()
  proc <- callr::r_bg(function(file, etag_file, port) {
    app <- list(call = function(req) {
      etag <- paste0('"', readLines(etag_file, warn = FALSE)[1], '"')
      bytes <- readBin(file, "raw", file.size(file))
      total <- length(bytes)
      # Content-Encoding: identity keeps httpuv from gzip/chunking the responses, which
      # stripped Content-Length from HEAD replies and made repeated HEADs fail with
      # "Invalid status line" (auditor's F18)
      base <- c("ETag" = etag, "Accept-Ranges" = "bytes", "Last-Modified" = "Tue, 15 Sep 2026 00:00:00 GMT",
                "Content-Encoding" = "identity", "Content-Type" = "application/octet-stream")
      if (identical(req$REQUEST_METHOD, "HEAD")) {
        return(list(status = 200L, headers = c(base, "Content-Length" = as.character(total)), body = ""))
      }
      range <- req$HTTP_RANGE; if_range <- req$HTTP_IF_RANGE
      if (!is.null(range) && (is.null(if_range) || identical(if_range, etag))) {
        start <- as.integer(sub("bytes=([0-9]+)-.*", "\\1", range))
        part <- bytes[(start + 1):total]
        return(list(status = 206L, headers = c(base, "Content-Range" = sprintf("bytes %d-%d/%d", start, total - 1, total),
                                                "Content-Length" = as.character(length(part))), body = part))
      }
      list(status = 200L, headers = c(base, "Content-Length" = as.character(total)), body = bytes)
    })
    httpuv::runServer("127.0.0.1", port, app)
  }, args = list(file = file, etag_file = etag_file, port = port))
  withr::defer(proc$kill(), envir = env)
  url <- sprintf("http://127.0.0.1:%d/x.duckdb", port)
  for (i in 1:50) {
    ok <- tryCatch(curl::curl_fetch_memory(url, curl::new_handle(nobody = TRUE))$status_code == 200, error = function(e) FALSE)
    if (isTRUE(ok)) return(url)
    Sys.sleep(0.1)
  }
  testthat::skip("loopback server did not start")
}

fixture_bytes <- function(dir, value) {
  path <- file.path(dir, sprintf("v%d.duckdb", value))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  DBI::dbExecute(con, sprintf("CREATE TABLE t AS SELECT %d AS n, repeat('x', 4000) AS pad FROM range(2000)", value))
  DBI::dbDisconnect(con, shutdown = TRUE)
  readBin(path, "raw", file.size(path))
}
