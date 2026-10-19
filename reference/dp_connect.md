# Connect to one or more datapond databases

Opens an in-memory DuckDB connection and attaches each requested
database read-only, either remotely from its `attach_url` (the default;
DuckDB's `httpfs` extension fetches byte ranges without requiring a full
download first) or from a local copy made with
[`dp_download()`](https://datapond-db.github.io/datapond-r/reference/dp_download.md).
Large remote queries can still transfer much of a file.

## Usage

``` r
dp_connect(
  id,
  local = FALSE,
  quiet = FALSE,
  config = getOption("datapond.duckdb_config", list())
)
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

- config:

  Named list of DuckDB configuration values, passed to
  [`duckdb::duckdb()`](https://r.duckdb.org/reference/duckdb.html)
  before any database is attached. Defaults to
  `getOption("datapond.duckdb_config", list())`. Use `memory_limit`,
  `threads`, `temp_directory`, and `max_temp_directory_size` to bound
  query resources. Values must be non-missing scalars and are converted
  to strings for DuckDB. DuckDB's memory limit does not include all R
  allocations. This argument was introduced in development version 0.1.1
  and is not in CRAN 0.1.0. With CRAN 0.1.0, set query limits after
  connecting using
  [`DBI::dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html),
  or use a direct DuckDB connection for startup limits.

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
