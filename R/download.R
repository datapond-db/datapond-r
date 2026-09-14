download_file <- function(url, dest, quiet = FALSE, resume = TRUE) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  part <- paste0(dest, ".part")
  res <- curl::multi_download(url, part, resume = resume, progress = !quiet)
  if (!isTRUE(res$success) || is.na(res$status_code) || res$status_code >= 400) {
    stop(sprintf("Download failed (HTTP %s): %s", res$status_code, url), call. = FALSE)
  }
  file.rename(part, dest)
  invisible(dest)
}

#' Download a database for local use
#'
#' Downloads the full `.duckdb` file so later queries run at disk speed.
#' Files are saved as `<id>.duckdb` under [dp_data_dir()] (or `path`), which is
#' where `dp_connect(id, local = TRUE)` looks for them.
#'
#' @param id Database id.
#' @param path Destination file or directory. Defaults to [dp_data_dir()].
#' @param quiet Suppress the progress bar?
#' @param resume Resume a partial download if one exists?
#' @return The local path, invisibly.
#' @export
#' @examples
#' \dontrun{
#' dp_download("dol-visas")
#' con <- dp_connect("dol-visas", local = TRUE)
#' }
dp_download <- function(id, path = NULL, quiet = FALSE, resume = TRUE) {
  db <- dp_get_database(id)
  dest <- if (is.null(path)) dp_local_path(id) else path
  if (dir.exists(dest)) dest <- file.path(dest, paste0(id, ".duckdb"))
  url <- db$download_url %||% db$attach_url
  if (is.null(url)) stop(sprintf("No download URL for '%s'.", id), call. = FALSE)
  if (!quiet) message(sprintf("Downloading %s (%s GB)...", db$name %||% id, db$size_gb %||% "?"))
  download_file(url, dest, quiet = quiet, resume = resume)
  if (!quiet) message("Saved to ", dest)
  invisible(dest)
}

#' Update a local database if the registry has a newer version
#'
#' Compares the registry's `updated` date with the local file's modification
#' time and re-downloads when the registry is newer.
#'
#' @inheritParams dp_download
#' @return The local path, invisibly.
#' @export
dp_update <- function(id, quiet = FALSE) {
  db <- dp_get_database(id)
  local <- dp_local_path(id)
  if (!file.exists(local)) {
    if (!quiet) message(sprintf("No local copy found. Downloading %s...", id))
    return(dp_download(id, quiet = quiet))
  }
  updated <- db$updated
  if (!is.null(updated)) {
    remote <- as.POSIXct(updated, tz = "UTC",
                         tryFormats = c("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"))
    if (!is.na(remote) && file.mtime(local) >= remote) {
      if (!quiet) message(sprintf("%s is already up to date.", id))
      return(invisible(local))
    }
  }
  if (!quiet) message(sprintf("Updating %s...", id))
  dp_download(id, quiet = quiet)
}
