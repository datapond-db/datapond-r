# datapond 0.1.1

* The identity probe used when a server's HEAD carries no validator reads one
  byte through a connection and closes it, so a server that ignores `Range`
  can no longer make the client buffer the whole database in memory just to
  read its headers. Covered by loopback tests where HEAD answers 405 and where
  `Range` is ignored (with a memory-profiling assertion).
* Real downloads work again: the response headers curl returns are a vector
  of lines, not one string, and a resumed transfer's `Content-Length` is only
  the remaining range (the total comes from `Content-Range`). A server that
  answers a stale `If-Range` with the whole file makes curl abort the resume;
  the client now discards the partial file and restarts. These paths are
  covered by a real loopback HTTP server test (httpuv + callr, Suggests).
* `dp_download()` streams to `<file>.part`, resumes only while the remote file
  is the same revision (a strong validator, ETag else Last-Modified, recorded
  beside the partial file; the ranged request is bound to it with `If-Range`
  and the GET response's validator is checked, so a file that changes between
  HEAD and GET is re-downloaded from scratch; no validator, no resume),
  validates the finished file as a DuckDB database, rejects a directory at the
  destination, and errors instead of warning when the destination cannot be
  replaced. An existing local copy is never damaged by a failed download.
* `dp_update()` compares the remote file's ETag (else Last-Modified) with the
  identity recorded at download time (`<file>.datapond.json`) instead of the
  file's modification time; equal sizes alone never count as current; the
  registry is re-fetched first.
* The registry response is decoded as UTF-8 explicitly, so the package works in
  a C/ASCII locale; an unparseable response falls back to the cached copy.
* `dp_download(path = "some/dir/")` creates the directory.

# datapond 0.1.0

* Initial release: `dp_list()`, `dp_databases()`, `dp_info()`, `dp_registry()`,
  `dp_connect()`, `dp_disconnect()`, `dp_download()`, `dp_update()`,
  `dp_describe()`. Mirrors the Python `datapond` package (0.1.3) against the
  same registry and Hugging Face-hosted DuckDB files.
