
# Identity of the remote file: ETag (Hugging Face sends the file's hash, also as
# X-Linked-Etag behind its CDN redirect), size and Last-Modified from a HEAD request.
# Returns an empty list when the request fails.
remote_identity <- function(url) {
  if (!is_url(url)) {
    if (!file.exists(url)) return(list())
    return(list(size = file.size(url), etag = unname(tools::md5sum(url))))
  }
  tryCatch({
    h <- curl::new_handle(nobody = TRUE, followlocation = TRUE, timeout = 30)
    res <- curl::curl_fetch_memory(url, handle = h)
    if (res$status_code >= 400) return(list())
    hd <- curl::parse_headers_list(res$headers)
    etag <- hd[["x-linked-etag"]] %||% hd[["etag"]]
    size <- hd[["x-linked-size"]] %||% hd[["content-length"]]
    out <- list()
    if (!is.null(etag)) out$etag <- gsub('^W/|"', "", etag)
    if (!is.null(size)) out$size <- suppressWarnings(as.numeric(size))
    if (!is.null(hd[["last-modified"]])) out$last_modified <- hd[["last-modified"]]
    out
  }, error = function(e) list())
}

sidecar_path <- function(dest) paste0(dest, ".datapond.json")

write_sidecar <- function(dest, id, url, identity) {
  data <- c(list(id = id, url = url, downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 local_size = file.size(dest)), identity)
  tryCatch(writeLines(jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE), sidecar_path(dest)),
           error = function(e) NULL)
  invisible(data)
}

read_sidecar <- function(dest) {
  p <- sidecar_path(dest)
  if (!file.exists(p)) return(list())
  tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE), error = function(e) list())
}

# Transfer `url` to `part`, resuming when the partial file still belongs to the
# same remote revision. `part_meta` records the identity the partial file was
# started against; a different ETag/size/Last-Modified restarts from zero, so a
# resume can never splice bytes from two versions of a file.
transfer <- function(url, part, identity, quiet = FALSE, resume = TRUE) {
  meta <- paste0(part, ".meta")
  if (file.exists(part)) {
    prior <- if (file.exists(meta)) tryCatch(jsonlite::fromJSON(meta), error = function(e) NULL) else NULL
    same <- !is.null(prior) && length(identity) > 0 && identical(prior$etag, identity$etag) &&
      identical(as.numeric(prior$size), as.numeric(identity$size)) &&
      identical(prior$last_modified, identity$last_modified)
    if (!resume || !same) {
      unlink(c(part, meta))
    }
  }
  if (!file.exists(part)) {
    writeLines(jsonlite::toJSON(identity, auto_unbox = TRUE), meta)
  }
  res <- curl::multi_download(url, part, resume = resume, progress = !quiet)
  if (!isTRUE(res$success) || is.na(res$status_code) || res$status_code >= 400) {
    stop(sprintf("Download failed (HTTP %s): %s", res$status_code, url), call. = FALSE)
  }
  unlink(meta)
  invisible(part)
}

# Open the finished file read-only to make sure it is a DuckDB database.
validate_database <- function(path) {
  con <- tryCatch(DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = TRUE),
                  error = function(e) stop("Downloaded file is not a readable DuckDB database: ",
                                           conditionMessage(e), call. = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, "SELECT 1")
  invisible(TRUE)
}

# Move the completed part file over the destination. `file.rename()` returns
# FALSE instead of erroring (and cannot cross filesystems), so the result is
# checked and a copy is attempted before giving up; the previous destination is
# untouched on failure.
install_file <- function(part, dest) {
  ok <- suppressWarnings(file.rename(part, dest))
  if (!isTRUE(ok)) {
    ok <- suppressWarnings(file.copy(part, dest, overwrite = TRUE))
    if (isTRUE(ok)) unlink(part)
  }
  if (!isTRUE(ok) || !file.exists(dest)) {
    stop(sprintf("Could not replace %s with the downloaded file (kept at %s).", dest, part), call. = FALSE)
  }
  invisible(dest)
}

download_file <- function(url, dest, quiet = FALSE, resume = TRUE, id = NULL) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  part <- paste0(dest, ".part")
  identity <- remote_identity(url)
  transfer(url, part, identity, quiet = quiet, resume = resume)
  if (!is.null(identity$size) && !is.na(identity$size) && file.size(part) != identity$size) {
    unlink(part)
    stop(sprintf("Download incomplete: %s of %s bytes.", file.size(part), identity$size), call. = FALSE)
  }
  validate_database(part)
  install_file(part, dest)
  write_sidecar(dest, id %||% basename(dest), url, identity)
  invisible(dest)
}

#' Download a database for local use
#'
#' Downloads the full `.duckdb` file so later queries run at disk speed.
#' Files are saved as `<id>.duckdb` under [dp_data_dir()] (or `path`), which is
#' where `dp_connect(id, local = TRUE)` looks for them.
#'
#' The transfer goes to `<file>.part` and replaces the destination only after
#' it is complete and opens as a DuckDB database, so an existing copy is never
#' damaged by a failed download. A partial download is resumed only when the
#' remote file is still the same revision; otherwise it restarts. A sidecar
#' `<file>.datapond.json` records the remote file identity for [dp_update()].
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
  if (dir.exists(dest) || grepl("[/\\\\]$", dest) || !grepl("\\.duckdb$", dest, ignore.case = TRUE)) {
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(sub("[/\\\\]+$", "", dest), paste0(id, ".duckdb"))
  }
  url <- db$download_url %||% db$attach_url
  if (is.null(url)) stop(sprintf("No download URL for '%s'.", id), call. = FALSE)
  if (!quiet) message(sprintf("Downloading %s (%s GB)...", db$name %||% id, db$size_gb %||% "?"))
  download_file(url, dest, quiet = quiet, resume = resume, id = id)
  if (!quiet) message("Saved to ", dest)
  invisible(dest)
}

# NULL when the local copy matches the remote file, else a short reason.
needs_update <- function(db, local) {
  url <- db$download_url %||% db$attach_url
  side <- read_sidecar(local)
  if (!is.null(side$local_size) && !identical(as.numeric(side$local_size), as.numeric(file.size(local)))) {
    return("local file changed since it was downloaded")
  }
  remote <- if (is.null(url)) list() else remote_identity(url)
  if (!is.null(side$etag) && !is.null(remote$etag)) {
    return(if (identical(side$etag, remote$etag)) NULL else "remote file changed")
  }
  if (!is.null(side$size) && !is.null(remote$size)) {
    return(if (identical(as.numeric(side$size), as.numeric(remote$size))) NULL else "remote size changed")
  }
  updated <- db$updated
  if (!is.null(updated)) {
    remote_dt <- as.POSIXct(updated, tz = "UTC",
                            tryFormats = c("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"))
    if (!is.na(remote_dt)) {
      # a bare date could mean any time that day: only a copy from a later day is trusted
      if (nchar(updated) <= 10) remote_dt <- remote_dt + 86399
      if (file.mtime(local) > remote_dt) return(NULL)
      return("registry lists a newer release")
    }
  }
  "no version information for the local copy"
}

#' Update a local database if the remote file has changed
#'
#' Compares the identity of the remote file (ETag and size, from a HEAD
#' request) with the one recorded when the local copy was downloaded, and
#' re-downloads when they differ. Copies without that record fall back to the
#' registry's `updated` date versus the file's modification time and are
#' re-downloaded whenever that comparison is inconclusive. The registry is
#' re-fetched first.
#'
#' @inheritParams dp_download
#' @return The local path, invisibly.
#' @export
dp_update <- function(id, quiet = FALSE) {
  db <- dp_get_database(id, refresh = TRUE)
  local <- dp_local_path(id)
  if (!file.exists(local)) {
    if (!quiet) message(sprintf("No local copy found. Downloading %s...", id))
    return(dp_download(id, quiet = quiet))
  }
  reason <- needs_update(db, local)
  if (is.null(reason)) {
    if (!quiet) message(sprintf("%s is already up to date.", id))
    return(invisible(local))
  }
  if (!quiet) message(sprintf("Updating %s (%s)...", id, reason))
  dp_download(id, quiet = quiet)
}
