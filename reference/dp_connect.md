# Connect to one or more datapond databases

Opens an in-memory DuckDB connection and attaches each requested
database read-only, either remotely from its `attach_url` (the default;
DuckDB's `httpfs` extension fetches only the byte ranges a query
touches, so there is no full download) or from a local copy made with
[`dp_download()`](https://datapond-db.github.io/datapond-r/reference/dp_download.md).

## Usage

``` r
dp_connect(id, local = FALSE, quiet = FALSE)
```

## Arguments

- id:

  One or more database ids (see
  [`dp_list()`](https://datapond-db.github.io/datapond-r/reference/dp_list.md)).

- local:

  Attach local copies under
  [`dp_data_dir()`](https://datapond-db.github.io/datapond-r/reference/dp_data_dir.md)
  instead of remote files?

- quiet:

  Suppress progress messages?

## Value

A `duckdb_connection` (a `DBIConnection`). Close it with
[`dp_disconnect()`](https://datapond-db.github.io/datapond-r/reference/dp_disconnect.md).

## Details

With a single `id` the database is made the default catalog (`USE`), so
tables can be referenced unqualified. With several ids, qualify tables
with the database id, double-quoting ids that contain a hyphen:
`"cms-medicare".physician_summary`.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- dp_connect("eoir")
DBI::dbGetQuery(con, "SELECT * FROM proceedings LIMIT 5")
dp_disconnect(con)

con <- dp_connect(c("cms-medicare", "openpayments"))
DBI::dbGetQuery(con, 'SELECT * FROM "cms-medicare".physician_summary LIMIT 5')
dp_disconnect(con)
} # }
```
