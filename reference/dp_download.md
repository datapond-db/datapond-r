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

## Examples

``` r
if (FALSE) { # \dontrun{
dp_download("dol-visas")
con <- dp_connect("dol-visas", local = TRUE)
} # }
```
