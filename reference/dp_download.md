# Download a database for local use

Downloads the full `.duckdb` file so later queries run at disk speed.
Files are saved as `<id>.duckdb` under
[`dp_data_dir()`](https://datapond-db.github.io/datapond-r/reference/dp_data_dir.md)
(or `path`), which is where `dp_connect(id, local = TRUE)` looks for
them.

## Usage

``` r
dp_download(id, path = NULL, quiet = FALSE, resume = TRUE)
```

## Arguments

- id:

  Database id.

- path:

  Destination file or directory. Defaults to
  [`dp_data_dir()`](https://datapond-db.github.io/datapond-r/reference/dp_data_dir.md).

- quiet:

  Suppress the progress bar?

- resume:

  Resume a partial download if one exists?

## Value

The local path, invisibly.

## Details

The transfer goes to `<file>.part` and replaces the destination only
after it is complete and opens as a DuckDB database, so an existing copy
is never damaged by a failed download. A partial download is resumed
only when the server identifies the file's revision (ETag, else
Last-Modified), the partial file was started against that revision, and
the ranged request is bound to it with `If-Range`; otherwise it
restarts. A sidecar `<file>.datapond.json` records the remote file
identity for
[`dp_update()`](https://datapond-db.github.io/datapond-r/reference/dp_update.md).

## Examples

``` r
if (FALSE) { # \dontrun{
dp_download("dol-visas")
con <- dp_connect("dol-visas", local = TRUE)
} # }
```
