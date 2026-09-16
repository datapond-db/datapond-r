DEFAULT_REGISTRY_URL <- "https://raw.githubusercontent.com/datapond-db/registry/main/registry.json"

registry_url <- function() getOption("datapond.registry_url", DEFAULT_REGISTRY_URL)
registry_ttl <- function() getOption("datapond.registry_ttl", 3600)
registry_file <- function() file.path(dp_cache_dir(), "registry.json")

cache_is_fresh <- function(path) {
  file.exists(path) &&
    as.numeric(difftime(Sys.time(), file.mtime(path), units = "secs")) < registry_ttl()
}

read_registry_file <- function(path) parse_registry_bytes(readBin(path, "raw", file.size(path)))

fetch_registry <- function() {
  url <- registry_url()
  path <- registry_file()
  raw <- tryCatch({
    if (!is_url(url)) {
      # A local file path: used by tests and offline mirrors.
      if (!file.exists(url)) stop("registry file not found: ", url)
      readBin(url, "raw", file.size(url))
    } else {
      h <- curl::new_handle(timeout = 15, followlocation = TRUE)
      res <- curl::curl_fetch_memory(url, handle = h)
      if (res$status_code >= 400) stop("HTTP ", res$status_code)
      res$content
    }
  }, error = function(e) {
    if (file.exists(path)) {
      warning("Could not fetch the datapond registry (", conditionMessage(e),
              "); using the cached copy.", call. = FALSE)
      return(NULL)
    }
    stop("Failed to fetch the datapond registry and no local cache is available: ",
         conditionMessage(e), call. = FALSE)
  })
  if (is.null(raw)) return(read_registry_file(path))
  # registry.json is UTF-8; rawToChar() yields unmarked text, which does not parse
  # in a C/ASCII locale unless the encoding is declared explicitly
  reg <- tryCatch(parse_registry_bytes(raw), error = function(e) {
    if (file.exists(path)) {
      warning("The fetched datapond registry could not be parsed (", conditionMessage(e),
              "); using the cached copy.", call. = FALSE)
      return(NULL)
    }
    stop("The fetched datapond registry could not be parsed and no local cache is available: ",
         conditionMessage(e), call. = FALSE)
  })
  if (is.null(reg)) return(read_registry_file(path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeBin(raw, path)
  reg
}

parse_registry_bytes <- function(raw) {
  txt <- rawToChar(raw)
  Encoding(txt) <- "UTF-8"
  reg <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (!is.list(reg) || is.null(reg$databases)) stop("no 'databases' element")
  reg
}

#' The datapond registry
#'
#' Fetches `registry.json` from GitHub (cached for an hour under
#' [dp_cache_dir()]; a stale cache is used if the network is unavailable).
#'
#' @param refresh Ignore the cache and fetch again?
#' @return The parsed registry: a list with a `databases` element, one list
#'   per database.
#' @export
#' @examples
#' \dontrun{
#' reg <- dp_registry()
#' length(reg$databases)
#' }
dp_registry <- function(refresh = FALSE) {
  path <- registry_file()
  if (!refresh && cache_is_fresh(path)) return(read_registry_file(path))
  fetch_registry()
}

dp_get_database <- function(id, refresh = FALSE) {
  stopifnot(is.character(id), length(id) == 1L, !is.na(id))
  dbs <- dp_registry(refresh = refresh)$databases
  ids <- vapply(dbs, function(d) d$id %||% NA_character_, character(1))
  i <- match(id, ids)
  if (is.na(i)) {
    stop(sprintf("Database '%s' not found in the registry. Available: %s",
                 id, paste(ids, collapse = ", ")), call. = FALSE)
  }
  structure(dbs[[i]], class = "datapond_db")
}

#' List available databases
#'
#' @return `dp_list()` returns a character vector of database ids;
#'   `dp_databases()` returns one row per database with its registry fields.
#' @export
#' @examples
#' \dontrun{
#' dp_list()
#' dp_databases()[, c("id", "rows", "size_gb")]
#' }
dp_list <- function() {
  vapply(dp_registry()$databases, function(d) d$id, character(1))
}

#' @rdname dp_list
#' @export
dp_databases <- function() {
  dbs <- dp_registry()$databases
  fields <- c("id", "name", "description", "rows", "tables", "size_gb", "source",
              "data_date_range", "last_rebuilt", "update_frequency", "maintainer",
              "license", "updated", "github", "huggingface", "attach_url", "dictionary_url")
  cols <- lapply(fields, function(f) {
    vals <- lapply(dbs, function(d) d[[f]])
    if (f %in% c("rows", "tables", "size_gb")) {
      vapply(vals, function(v) if (is.null(v)) NA_real_ else as.numeric(v), numeric(1))
    } else {
      vapply(vals, function(v) if (is.null(v)) NA_character_ else as.character(v), character(1))
    }
  })
  names(cols) <- fields
  as_tbl(as.data.frame(cols, stringsAsFactors = FALSE))
}

#' Information about one database
#'
#' @param id Database id.
#' @return The registry entry (a list of class `datapond_db`), printed in a
#'   readable layout.
#' @export
#' @examples
#' \dontrun{
#' dp_info("eoir")
#' }
dp_info <- function(id) dp_get_database(id)

#' @export
print.datapond_db <- function(x, ...) {
  cat("  ", x$name %||% x$id, "\n", sep = "")
  cat(sprintf("  %s rows | %s tables | %s GB\n", fmt_rows(x$rows), x$tables %||% "?", x$size_gb %||% "?"))
  cat("  Source: ", x$source %||% "Unknown", "\n", sep = "")
  if (!is.null(x$data_date_range)) cat("  Coverage: ", x$data_date_range, "\n", sep = "")
  if (!is.null(x$last_rebuilt)) cat("  Last rebuilt: ", x$last_rebuilt, "\n", sep = "")
  if (!is.null(x$github)) cat("  GitHub: ", sub("^https://", "", x$github), "\n", sep = "")
  if (!is.null(x$huggingface)) cat("  Hugging Face: ", sub("^https://", "", x$huggingface), "\n", sep = "")
  if (!is.null(x$dictionary_url)) cat("  Data dictionary: ", x$dictionary_url, "\n", sep = "")
  if (!is.null(x$maintainer)) cat("  Maintainer: ", x$maintainer, "\n", sep = "")
  if (!is.null(x$license)) cat("  License: ", x$license, "\n", sep = "")
  invisible(x)
}
