
# Identity of the remote file: ETag (Hugging Face sends the file's hash, also as
# X-Linked-Etag behind its CDN redirect), size and Last-Modified from a HEAD request.
# Returns an empty list when the request fails.
remote_identity <- function(url) {
  if (!is_url(url)) {
    if (!file.exists(url)) return(list())
    return(list(size = file.size(url), etag = unname(tools::md5sum(url))))
  }
  head <- tryCatch({
    h <- curl::new_handle(nobody = TRUE, followlocation = TRUE, timeout = 30)
    res <- curl::curl_fetch_memory(url, handle = h)
    if (res$status_code >= 400) list() else identity_from_headers(curl::parse_headers_list(res$headers))
  }, error = function(e) list())
  if (!is.null(strong_validator(head))) return(head)
  # Some servers answer HEAD without validators (or not at all): ask for the first byte
  # instead and read the validators and the total length from that response.
  tryCatch({
    h <- curl::new_handle(followlocation = TRUE, timeout = 30, httpheader = "Range: bytes=0-0")
    # A server may ignore Range and answer 200 with the whole entity. Read one byte
    # through a connection and close it, so the probe never buffers a multi-GB
    # database in memory just to read its headers (auditor's F19).
    con <- curl::curl(url, handle = h)
    on.exit(close(con), add = TRUE)
    suppressWarnings(open(con, "rb"))
    readBin(con, raw(), n = 1L)
    res <- curl::handle_data(h)
    if (res$status_code >= 400) return(head)
    hd <- curl::parse_headers_list(res$headers)
    out <- identity_from_headers(hd)
    if (res$status_code == 206) {
      total <- if (!is.null(hd[["content-range"]])) suppressWarnings(as.numeric(sub(".*/", "", hd[["content-range"]]))) else NA_real_
      out$size <- if (!is.na(total)) total else NULL
    }
    if (length(out) > 0) out else head
  }, error = function(e) head)
}

identity_from_headers <- function(hd) {
  etag <- hd[["x-linked-etag"]] %||% hd[["etag"]]
  size <- hd[["x-linked-size"]] %||% hd[["content-length"]]
  out <- list()
  if (!is.null(etag) && nzchar(etag)) {
    # Weak ETags do not identify byte-for-byte identical representations and
    # must never be promoted to a strong If-Range validator (RFC 9110 13.1.5).
    if (startsWith(etag, "W/")) out$weak_etag <- etag
    else out$etag <- gsub('^"|"$', "", etag)
  }
  if (!is.null(size)) out$size <- suppressWarnings(as.numeric(size))
  if (!is.null(hd[["last-modified"]])) out$last_modified <- hd[["last-modified"]]
  out
}

# A validator that identifies a revision: the ETag, or failing that Last-Modified.
# Size alone is not one (two revisions can have the same length).
strong_validator <- function(identity) {
  # A quoted empty opaque tag (ETag: "") is also a valid strong validator.
  if (!is.null(identity$etag)) return(identity$etag)
  # If-Range must not substitute a date when an entity tag is present but weak.
  if (!is.null(identity$weak_etag)) return(NULL)
  identity$last_modified
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

# Transfer `url` to `part`. A partial file is resumed only when (a) the server gave a
# strong validator (ETag, else Last-Modified), (b) the partial file was started against
# that same validator, and (c) the ranged request is bound to it with If-Range, so the
# server sends the whole file instead of a range if the revision changed meanwhile.
# The GET response's own validator is compared with the one the transfer was planned
# against; a mismatch (the file changed between HEAD and GET) discards the bytes and
# starts over once when resuming. A fresh full response adopts its own identity
# without another download. Without any validator there is no resume at all.
transfer <- function(url, part, identity, quiet = FALSE, resume = TRUE, attempts = 2) {
  meta <- paste0(part, ".meta")
  validator <- strong_validator(identity)
  for (attempt in seq_len(attempts)) {
    resumable <- resume && !is.null(validator)
    if (file.exists(part)) {
      prior <- if (file.exists(meta)) tryCatch(jsonlite::fromJSON(meta), error = function(e) NULL) else NULL
      if (resume && !is.null(prior) && isTRUE(prior$complete) &&
          identical(prior$url, url) && length(identity) == 0L &&
          identical(as.numeric(prior$downloaded_size), as.numeric(file.size(part)))) {
        stop("Could not verify the remote revision; completed download kept at ",
             part, ". Retry later or use resume = FALSE to download afresh.", call. = FALSE)
      }
      same <- resumable && !is.null(prior) && identical(prior$url, url) &&
        identical(strong_validator(prior), validator)
      if (!same) unlink(c(part, meta))
      if (same && isTRUE(prior$complete) &&
          identical(as.numeric(prior$downloaded_size), as.numeric(file.size(part))) &&
          (is.null(identity$size) || is.na(identity$size) || identity$size == file.size(part))) {
        # A previous transfer completed but installation failed (e.g. a locked
        # destination). Reuse it only after rechecking its URL, revision and size.
        return(invisible(list(part = part, identity = identity)))
      }
    }
    if (!file.exists(part)) {
      writeLines(jsonlite::toJSON(c(identity, list(url = url)), auto_unbox = TRUE), meta)
    }
    headers <- if (resumable && file.exists(part) && file.size(part) > 0) {
      c(paste0("If-Range: ", if (!is.null(identity$etag)) paste0('"', identity$etag, '"') else identity$last_modified))
    } else character()
    resuming <- resumable && file.exists(part) && file.size(part) > 0
    res <- curl::multi_download(url, part, resume = resumable, progress = !quiet, httpheader = headers)
    ok <- isTRUE(res$success) && !is.na(res$status_code) && res$status_code < 400
    rejected <- !ok && resuming && res$status_code %in% c(200L, 416L)
    if (rejected && attempt < attempts) {
      # A server that answers a mismatched If-Range with the whole entity (HTTP 200) makes
      # curl abort the resume; the partial file belongs to another revision, so discard
      # it and transfer afresh against the server's current identity. An
      # unsatisfiable range (416) also restarts. Network errors, interrupted
      # 206 responses and server outages keep the partial bytes for retry.
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
    changed <- if (!is.null(identity$etag)) {
      !is.null(got$etag) && !identical(got$etag, identity$etag)
    } else {
      !is.null(got$last_modified) && !identical(got$last_modified, identity$last_modified)
    }
    if (resuming && !is.null(validator) && (!is.null(got$weak_etag) || changed)) {
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
    # A fresh HTTP body describes its own revision. Missing GET headers must
    # not inherit a stale tag, date or length from the earlier HEAD response.
    # A successful conditional range may retain the identity bound by If-Range.
    final_identity <- if (!resuming && is_url(url)) got else {
      if (length(got) > 0) utils::modifyList(identity, got) else identity
    }
    # GET's tag supersedes HEAD's tag, including changes in validator strength.
    if (!is.null(got$weak_etag)) final_identity$etag <- NULL
    if (!is.null(got$etag)) final_identity$weak_etag <- NULL
    writeLines(jsonlite::toJSON(c(final_identity,
      list(url = url, complete = TRUE, downloaded_size = file.size(part))),
      auto_unbox = TRUE), meta)
    return(invisible(list(part = part, identity = final_identity)))
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
    downloaded_size <- file.size(part)
    unlink(c(part, paste0(part, ".meta")))
    stop(sprintf("Download incomplete: %s of %s bytes.", downloaded_size, identity$size), call. = FALSE)
  }
  tryCatch(validate_database(part), error = function(e) {
    # Complete transfer is not proof of valid database bytes. A later retry must
    # fetch afresh after validation fails, while preserving the installed copy.
    unlink(c(part, paste0(part, ".meta")))
    stop(e)
  })
  install_file(part, dest)
  unlink(paste0(part, ".meta"))
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
  # ETags are scoped to a resource URL; equal tags from two mirrors need not
  # identify the same bytes.
  if (!is.null(side$url) && !identical(side$url, url)) return("download URL changed")
  if (!is.null(side$local_size) && !identical(as.numeric(side$local_size), as.numeric(file.size(local)))) {
    return("local file changed since it was downloaded")
  }
  remote <- if (is.null(url)) list() else remote_identity(url)
  if (!is.null(side$etag) && !is.null(remote$etag)) {
    return(if (identical(side$etag, remote$etag)) NULL else "remote file changed")
  }
  # Tag changes, including changes in strength, must precede date fallback.
  # Equal weak tags alone do not establish byte identity.
  side_tag <- side$weak_etag %||% side$etag
  remote_tag <- remote$weak_etag %||% remote$etag
  if (!is.null(side_tag) && !is.null(remote_tag) &&
      !identical(side_tag, remote_tag)) return("remote file changed")
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
