attach_sql <- function(con, source, alias) {
  paste0("ATTACH ", DBI::dbQuoteString(con, source),
         " AS ", DBI::dbQuoteIdentifier(con, alias), " (READ_ONLY)")
}

#' Connect to one or more datapond databases
#'
#' Opens an in-memory DuckDB connection and attaches each requested database
#' read-only, either remotely from its `attach_url` (the default; DuckDB's
#' `httpfs` extension fetches only the byte ranges a query touches, so there is
#' no full download) or from a local copy made with [dp_download()].
#'
#' With a single `id` the database is made the default catalog (`USE`), so
#' tables can be referenced unqualified. With several ids, qualify tables with
#' the database id, double-quoting ids that contain a hyphen:
#' `"cms-medicare".physician_summary`.
#'
#' @param id One or more database ids (see [dp_list()]).
#' @param local Attach local copies under [dp_data_dir()] instead of remote
#'   files?
#' @param quiet Suppress progress messages?
#' @return A `duckdb_connection` (a `DBIConnection`). Close it with
#'   [dp_disconnect()].
#' @export
#' @examples
#' \dontrun{
#' con <- dp_connect("eoir")
#' DBI::dbGetQuery(con, "SELECT * FROM proceedings LIMIT 5")
#' dp_disconnect(con)
#'
#' con <- dp_connect(c("cms-medicare", "openpayments"))
#' DBI::dbGetQuery(con, 'SELECT * FROM "cms-medicare".physician_summary LIMIT 5')
#' dp_disconnect(con)
#' }
dp_connect <- function(id, local = FALSE, quiet = FALSE) {
  stopifnot(is.character(id), length(id) >= 1L, !anyNA(id))
  entries <- lapply(id, dp_get_database)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  ok <- FALSE
  on.exit(if (!ok) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  sources <- vapply(entries, function(db) {
    if (local) dp_local_path(db$id, must_exist = TRUE) else db$attach_url %||% ""
  }, character(1))
  if (any(sources == "")) stop("Registry entry has no attach_url.", call. = FALSE)

  if (any(is_url(sources))) {
    DBI::dbExecute(con, "INSTALL httpfs")
    DBI::dbExecute(con, "LOAD httpfs")
  }

  for (i in seq_along(entries)) {
    db <- entries[[i]]
    if (!quiet) {
      message(sprintf("Connecting to %s (%s)...", db$name %||% db$id,
                      if (local) "local" else paste0(db$size_gb %||% "?", " GB remote")))
    }
    DBI::dbExecute(con, attach_sql(con, sources[[i]], db$id))
  }

  if (length(entries) == 1L) {
    DBI::dbExecute(con, paste0("USE ", DBI::dbQuoteIdentifier(con, entries[[1]]$id)))
  }

  if (!quiet) {
    n <- DBI::dbGetQuery(con, paste(
      "SELECT count(*) AS n FROM information_schema.tables",
      "WHERE table_schema NOT IN ('information_schema', 'pg_catalog')",
      "AND table_name NOT IN ('_metadata', '_columns')"))$n
    message(sprintf("Connected. %d tables available%s.", n,
                    if (length(entries) > 1L) sprintf(" across %d databases", length(entries)) else ""))
  }
  ok <- TRUE
  con
}

#' Close a datapond connection
#'
#' @param con A connection from [dp_connect()].
#' @return `TRUE`, invisibly.
#' @export
dp_disconnect <- function(con) invisible(DBI::dbDisconnect(con, shutdown = TRUE))
