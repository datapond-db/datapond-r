try_query <- function(con, primary, fallback, params = NULL) {
  tryCatch(DBI::dbGetQuery(con, primary, params = params),
           error = function(e) DBI::dbGetQuery(con, fallback, params = params))
}

# Columns of a dictionary table in the current (USE'd) database, or NULL if
# the table does not exist. Databases contributed by different people carry
# slightly different _metadata/_columns schemas, so every query below is built
# from the columns that are actually present.
dict_columns <- function(con, table) {
  tryCatch(DBI::dbGetQuery(con, paste0("DESCRIBE ", table))$column_name,
           error = function(e) NULL)
}

select_or_null <- function(have, want, types) {
  vapply(seq_along(want), function(i) {
    if (want[i] %in% have) want[i] else sprintf("NULL::%s AS %s", types[i], want[i])
  }, character(1))
}

describe_database <- function(con) {
  have <- dict_columns(con, "_metadata")
  if (!is.null(have) && "table_name" %in% have) {
    sel <- select_or_null(have, c("table_name", "row_count", "description"),
                          c("VARCHAR", "BIGINT", "VARCHAR"))
    df <- DBI::dbGetQuery(con, paste(
      "SELECT", paste(sel, collapse = ", "), "FROM _metadata",
      "WHERE table_name NOT IN ('_metadata', '_columns') ORDER BY row_count DESC NULLS LAST, table_name"))
    return(as_tbl(df))
  }
  as_tbl(DBI::dbGetQuery(con, paste(
    "SELECT table_name, NULL::BIGINT AS row_count, NULL::VARCHAR AS description",
    "FROM information_schema.tables WHERE table_schema = 'main'",
    "AND table_name NOT IN ('_metadata', '_columns') ORDER BY table_name")))
}

describe_table <- function(con, table) {
  have <- dict_columns(con, "_columns")
  if (!is.null(have) && all(c("table_name", "column_name") %in% have)) {
    sel <- select_or_null(have, c("column_name", "data_type", "null_pct", "example_value", "join_hint"),
                          c("VARCHAR", "VARCHAR", "DOUBLE", "VARCHAR", "VARCHAR"))
    extra <- setdiff(have, c("table_name", "column_name", "data_type", "null_pct", "example_value",
                             "join_hint", "source_file"))
    df <- DBI::dbGetQuery(con, paste(
      "SELECT", paste(c(sel, extra), collapse = ", "), "FROM _columns WHERE table_name = ? ORDER BY rowid"),
      params = list(table))
    if (nrow(df) > 0) return(as_tbl(df))
  }
  as_tbl(DBI::dbGetQuery(con, paste(
    "SELECT column_name, data_type, NULL::DOUBLE AS null_pct,",
    "NULL::VARCHAR AS example_value, NULL::VARCHAR AS join_hint",
    "FROM information_schema.columns WHERE table_name = ? ORDER BY ordinal_position"),
    params = list(table)))
}

search_columns <- function(con, pattern) {
  have <- dict_columns(con, "_columns")
  if (!is.null(have) && all(c("table_name", "column_name") %in% have)) {
    sel <- select_or_null(have, c("table_name", "column_name", "data_type", "join_hint"),
                          c("VARCHAR", "VARCHAR", "VARCHAR", "VARCHAR"))
    return(as_tbl(DBI::dbGetQuery(con, paste(
      "SELECT", paste(sel, collapse = ", "), "FROM _columns",
      "WHERE UPPER(column_name) LIKE '%' || UPPER(?) || '%' ORDER BY table_name, column_name"),
      params = list(pattern))))
  }
  as_tbl(DBI::dbGetQuery(con, paste(
    "SELECT table_name, column_name, data_type, NULL::VARCHAR AS join_hint",
    "FROM information_schema.columns WHERE table_schema = 'main'",
    "AND UPPER(column_name) LIKE '%' || UPPER(?) || '%' ORDER BY table_name, column_name"),
    params = list(pattern)))
}

#' Explore a database's data dictionary
#'
#' Every datapond database ships `_metadata` (one row per table) and
#' `_columns` (types, null rates, example values, join hints). `dp_describe()`
#' reads them and falls back to `information_schema` when they are absent.
#'
#' @param x A database id, or an open connection from [dp_connect()].
#' @param table Describe the columns of this table instead of listing tables.
#' @param search Find columns whose name contains this text (case-insensitive).
#' @return A data frame (a tibble when the tibble package is installed).
#' @export
#' @examples
#' \dontrun{
#' dp_describe("eoir")
#' dp_describe("eoir", table = "proceedings")
#' dp_describe("eoir", search = "judge")
#' }
dp_describe <- function(x, table = NULL, search = NULL) {
  if (inherits(x, "DBIConnection")) {
    con <- x
  } else {
    con <- dp_connect(x, quiet = TRUE)
    on.exit(dp_disconnect(con), add = TRUE)
  }
  if (!is.null(search)) return(search_columns(con, search))
  if (!is.null(table)) return(describe_table(con, table))
  describe_database(con)
}
