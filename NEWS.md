# datapond 0.1.1

* `dp_download()` streams to `<file>.part`, resumes only while the remote file
  is the same revision (ETag/size/Last-Modified recorded beside the partial
  file), validates the finished file as a DuckDB database, and errors instead
  of warning when the destination cannot be replaced. An existing local copy is
  never damaged by a failed download.
* `dp_update()` compares the remote file's ETag/size with the identity recorded
  at download time (`<file>.datapond.json`) instead of the file's modification
  time, and re-fetches the registry first.
* The registry response is decoded as UTF-8 explicitly, so the package works in
  a C/ASCII locale; an unparseable response falls back to the cached copy.
* `dp_download(path = "some/dir/")` creates the directory.

# datapond 0.1.0

* Initial release: `dp_list()`, `dp_databases()`, `dp_info()`, `dp_registry()`,
  `dp_connect()`, `dp_disconnect()`, `dp_download()`, `dp_update()`,
  `dp_describe()`. Mirrors the Python `datapond` package (0.1.3) against the
  same registry and Hugging Face-hosted DuckDB files.
