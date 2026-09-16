
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
    identity_from_headers(curl::parse_headers_list(res$headers))
  }, error = function(e) list())
}

identity_from_headers <- function(hd) {
  etag <- hd[["x-linked-etag"]] %||% hd[["etag"]]
  size <- hd[["x-linked-size"]] %||% hd[["content-length"]]
  out <- list()
  if (!is.null(etag)) out$etag <- gsub('^W/|"', "", etag)
  if (!is.null(size)) out$size <- suppressWarnings(as.numeric(size))
  if (!is.null(hd[["last-modified"]])) out$last_modified <- hd[["last-modified"]]
  out
}

# A validator that identifies a revision: the ETag, or failing that Last-Modified.
# Size alone is not one (two revisions can have the same length).
strong_validator <- function(identity) identity$etag %||% identity$last_modified

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

# Transfer `url` to `part`. A partial file is resumed only when (a) the server gave a
# strong validator (ETag, else Last-Modified), (b) the partial file was started against
# that same validator, and (c) the ranged request is bound to it with If-Range, so the
# server sends the whole file instead of a range if the revision changed meanwhile.
# The GET response's own validator is compared with the one the transfer was planned
# against; a mismatch (the file changed between HEAD and GET) discards the bytes and
# starts over once. Without any validator there is no resume at all.
transfer <- function(url, part, identity, quiet = FALSE, resume = TRUE, attempts = 2) {
  meta <- paste0(part, ".meta")
  validator <- strong_validator(identity)
  for (attempt in seq_len(attempts)) {
    resumable <- resume && !is.null(validator)
    if (file.exists(part)) {
      prior <- if (file.exists(meta)) tryCatch(jsonlite::fromJSON(meta), error = function(e) NULL) else NULL
      same <- resumable && !is.null(prior) && identical(strong_validator(prior), validator)
      if (!same) unlink(c(part, meta))
    }
    if (!file.exists(part)) {
      writeLines(jsonlite::toJSON(identity, auto_unbox = TRUE), meta)
    }
    headers <- if (resumable && file.exists(part) && file.size(part) > 0) {
      c(paste0("If-Range: ", if (!is.null(identity$etag)) paste0('"', identity$etag, '"') else identity$last_modified))
    } else character()
    resuming <- resumable && file.exists(part) && file.size(part) > 0
    res <- curl::multi_download(url, part, resume = resumable, progress = !quiet, httpheader = headers)
    ok <- isTRUE(res$success) && !is.na(res$status_code) && res$status_code < 400
    if (!ok && resuming && attempt < attempts) {
      # A server that answers a mismatched If-Range with the whole entity (HTTP 200) makes
      # curl abort the resume; the partial file belongs to another revision, so discard
      # it and transfer afresh against the server's current identity.
      if (!quiet) message("Resume rejected by the server; restarting the download.")
      unlink(c(part, meta))
      identity <- remote_identity(url)
      validator <- strong_validator(identity)
      next
    }
    if (!ok) {
      stop(sprintf("Download failed (HTTP %s): %s", res$status_code, url), call. = FALSE)
    }
    got <- response_identity(res)
    got_validator <- strong_validator(got)
    if (!is.null(validator) && !is.null(got_validator) && !identical(got_validator, validator)) {
      # the remote file changed while we were transferring: never install the mixture
      unlink(c(part, meta))
      if (attempt < attempts) {
        if (!quiet) message("The remote file changed during the download; starting over.")
        identity <- if (length(got) > 0) got else remote_identity(url)
        validator <- strong_validator(identity)
        next
      }
      stop("The remote file kept changing during the download; try again later.", call. = FALSE)
    }
    unlink(meta)
    return(invisible(list(part = part, identity = if (length(got) > 0) utils::modifyList(identity, got) else identity)))
  }
}

# Identity from a multi_download() result row. Its `headers` column holds a character
# vector of header lines (one element per line, possibly several for redirects), not one
# string. Content-Length is only the file's length on a 200; on a 206 (resumed range)
# the total comes from Content-Range, so a range response never masquerades as the
# full-file length.
response_identity <- function(res) {
  hdr <- tryCatch(res$headers[[1]], error = function(e) NULL)
  if (is.null(hdr) || length(hdr) == 0 || !any(nzchar(hdr))) return(list())
  # with redirects the vector holds several responses; the final one describes the file
  starts <- grep("^HTTP/", hdr)
  if (length(starts) > 1) hdr <- hdr[max(starts):length(hdr)]
  hd <- tryCatch(curl::parse_headers_list(paste(hdr, collapse = "\r\n")), error = function(e) NULL)
  if (is.null(hd)) return(list())
  out <- identity_from_headers(hd)
  status <- suppressWarnings(as.integer(res$status_code[[1]]))
  range <- hd[["content-range"]]
  if (!is.na(status) && status == 206) {
    total <- if (!is.null(range)) suppressWarnings(as.numeric(sub(".*/", "", range))) else NA_real_
    out$size <- if (!is.na(total)) total else NULL
  }
  out
}

# Open the finished file read-only to make sure it is a DuckDB database.
validate_database <- function(path) {
  if (dir.exists(path)) stop("Expected a database file but found a directory: ", path, call. = FALSE)
  con <- tryCatch(DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = TRUE),
                  error = function(e) stop("Downloaded file is not a readable DuckDB database: ",
                                           conditionMessage(e), call. = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, "SELECT 1")
  invisible(TRUE)
}

# Move the completed part file over the destination. The destination must not be a
# directory; `file.rename()` returns FALSE instead of erroring (and cannot cross
# filesystems), so the result is checked and a copy to a temporary sibling followed by a
# rename is attempted before giving up. The previous destination survives every failure.
install_file <- function(part, dest) {
  if (dir.exists(dest)) {
    stop(sprintf("Destination %s is a directory; give a file path ending in .duckdb.", dest), call. = FALSE)
  }
  ok <- suppressWarnings(file.rename(part, dest))
  if (!isTRUE(ok)) {
    staged <- paste0(dest, ".staged")
    ok <- suppressWarnings(file.copy(part, staged, overwrite = TRUE)) && suppressWarnings(file.rename(staged, dest))
    unlink(staged)
    if (isTRUE(ok)) unlink(part)
  }
  if (!isTRUE(ok) || !file.exists(dest) || dir.exists(dest)) {
    stop(sprintf("Could not replace %s with the downloaded file (kept at %s).", dest, part), call. = FALSE)
  }
  invisible(dest)
}

download_file <- function(url, dest, quiet = FALSE, resume = TRUE, id = NULL) {
  if (dir.exists(dest)) {
    stop(sprintf("Destination %s is a directory; give a file path ending in .duckdb.", dest), call. = FALSE)
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  part <- paste0(dest, ".part")
  identity <- remote_identity(url)
  done <- transfer(url, part, identity, quiet = quiet, resume = resume)
  identity <- done$identity
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
#' server identifies the file's revision (ETag, else Last-Modified), the partial
#' file was started against that revision, and the ranged request is bound to it
#' with `If-Range`; otherwise it restarts. A sidecar `<file>.datapond.json`
#' records the remote file identity for [dp_update()].
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

# NULL when the local copy is verifiably the remote revision, else a short reason.
# Only a strong validator (ETag, else Last-Modified) can declare a copy current;
# equal sizes are not evidence, so without a validator the copy is re-downloaded.
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
  if (!is.null(side$last_modified) && !is.null(remote$last_modified)) {
    return(if (identical(side$last_modified, remote$last_modified)) NULL else "remote file changed")
  }
  if (length(side) > 0 && length(remote) > 0) return("remote revision cannot be verified (no ETag or Last-Modified)")
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
#' Compares the identity of the remote file (ETag, else Last-Modified, from a
#' HEAD request) with the one recorded when the local copy was downloaded, and
#' re-downloads when they differ or when the revision cannot be verified. Copies
#' without that record fall back to the registry's `updated` date versus the
#' file's modification time and are re-downloaded whenever that comparison is
#' inconclusive. The registry is re-fetched first.
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
