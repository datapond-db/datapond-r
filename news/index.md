# Changelog

## datapond 0.1.1

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

## datapond 0.1.0

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
