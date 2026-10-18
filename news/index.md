# Changelog

## datapond 0.1.1 (development)

- Interrupted ranged transfers retain their partial bytes for the next
  call; rejected or unsatisfiable ranges still restart safely.

- A transient identity-probe failure preserves completed downloads for
  retry. Date-bound resumes can adopt a strong response tag without
  re-downloading.

- Fresh HTTP responses no longer inherit stale HEAD validators. Changes
  in ETag strength trigger updates even when Last-Modified is unchanged.

- Incomplete downloads report the received byte count and clear
  temporary bytes and completion metadata before a retry.

- `dp_connect(config = ...)` and `options(datapond.duckdb_config = ...)`
  allow memory, thread and spill limits before database attachment.

- Weak ETags no longer enable a ranged resume. Update and
  partial-download identities are scoped to the source URL, so a new
  mirror cannot accidentally match an unrelated ETag.

- Completed downloads retain their metadata until installation succeeds.
  If installation fails, a retry reuses the completed file after
  rechecking its URL, revision and size, instead of downloading it
  again.

- A failed database validation clears the completed-transfer marker so
  retry fetches fresh bytes. A full fresh response uses its own identity
  without a redundant transfer; resumed responses still restart after
  validator changes.

- Empty quoted ETags remain valid strong validators, and differing weak
  ETags trigger an update even when Last-Modified is unchanged.

- DuckDB configuration accepts scalar numeric and logical values as well
  as strings, with clear errors for missing or vector values.

- Installation documentation now links the live CRAN release (0.1.0,
  published September 27, 2026) and distinguishes development-only
  changes.

- The identity probe used when a server’s HEAD carries no validator
  reads one byte through a connection and closes it, so a server that
  ignores `Range` can no longer make the client buffer the whole
  database in memory just to read its headers. Covered by loopback tests
  where HEAD answers 405 and where `Range` is ignored (with a
  memory-profiling assertion).

- Real downloads work again: the response headers curl returns are a
  vector of lines, not one string, and a resumed transfer’s
  `Content-Length` is only the remaining range (the total comes from
  `Content-Range`). A server that answers a stale `If-Range` with the
  whole file makes curl abort the resume; the client now discards the
  partial file and restarts. These paths are covered by a real loopback
  HTTP server test (httpuv + callr, Suggests).

- [`dp_download()`](https://datapond-db.github.io/datapond-r/reference/dp_download.md)
  streams to `<file>.part`, resumes only while the remote file is the
  same revision (a strong validator, ETag else Last-Modified, recorded
  beside the partial file; the ranged request is bound to it with
  `If-Range` and the GET response’s validator is checked, so a file that
  changes between HEAD and GET is re-downloaded from scratch; no
  validator, no resume), validates the finished file as a DuckDB
  database, rejects a directory at the destination, and errors instead
  of warning when the destination cannot be replaced. An existing local
  copy is never damaged by a failed download.

- [`dp_update()`](https://datapond-db.github.io/datapond-r/reference/dp_update.md)
  compares the remote file’s ETag (else Last-Modified) with the identity
  recorded at download time (`<file>.datapond.json`) instead of the
  file’s modification time; equal sizes alone never count as current;
  the registry is re-fetched first.

- The registry response is decoded as UTF-8 explicitly, so the package
  works in a C/ASCII locale; an unparseable response falls back to the
  cached copy.

- `dp_download(path = "some/dir/")` creates the directory.

## datapond 0.1.0 (CRAN: 2026-09-27)

CRAN release: 2026-09-27

- Initial release:
  [`dp_list()`](https://datapond-db.github.io/datapond-r/reference/dp_list.md),
  [`dp_databases()`](https://datapond-db.github.io/datapond-r/reference/dp_list.md),
  [`dp_info()`](https://datapond-db.github.io/datapond-r/reference/dp_info.md),
  [`dp_registry()`](https://datapond-db.github.io/datapond-r/reference/dp_registry.md),
  [`dp_connect()`](https://datapond-db.github.io/datapond-r/reference/dp_connect.md),
  [`dp_disconnect()`](https://datapond-db.github.io/datapond-r/reference/dp_disconnect.md),
  [`dp_download()`](https://datapond-db.github.io/datapond-r/reference/dp_download.md),
  [`dp_update()`](https://datapond-db.github.io/datapond-r/reference/dp_update.md),
  [`dp_describe()`](https://datapond-db.github.io/datapond-r/reference/dp_describe.md).
  Mirrors the Python `datapond` package (0.1.3) against the same
  registry and Hugging Face-hosted DuckDB files.
