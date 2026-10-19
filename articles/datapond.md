# Getting started with datapond

datapond is a registry of curated DuckDB databases built from public
data. Each database is a single `.duckdb` file hosted on Hugging Face.
This package attaches those files over HTTP so that only the byte ranges
your query touches are transferred, or downloads them once for local
use.

## Install

The released package is available on
[CRAN](https://CRAN.R-project.org/package=datapond):

``` r

install.packages("datapond")
```

CRAN 0.1.0 was published September 27, 2026. This development vignette
also describes the 0.1.1 resource controls, available from
`pak::pak("datapond-db/datapond-r")` until the next CRAN release.

## Browse

``` r

library(datapond)
dp_list()
dp_databases()[, c("id", "rows", "size_gb", "data_date_range")]
dp_info("eoir")
```

## Query remotely

[`dp_connect()`](https://datapond-db.github.io/datapond-r/reference/dp_connect.md)
returns an ordinary DuckDB `DBIConnection`:

``` r

con <- dp_connect("eoir")
DBI::dbGetQuery(con, "SELECT * FROM proceedings LIMIT 5")
```

For bounded queries in the development version, configure DuckDB before
attachment:

``` r

dp_disconnect(con)
con <- dp_connect("eoir", config = list(
  memory_limit = "1GB", threads = "2",
  temp_directory = tempfile("datapond-spill-"),
  max_temp_directory_size = "2GB"
))
```

The same list can be set with
`options(datapond.duckdb_config = list(...))`. Leave headroom for R and
the desktop: DuckDB’s memory limit is not a limit on the whole R
process. Filter and aggregate before collecting data into R.

Every database ships a data dictionary;
[`dp_describe()`](https://datapond-db.github.io/datapond-r/reference/dp_describe.md)
reads it:

``` r

dp_describe(con)                         # tables
dp_describe(con, table = "proceedings")  # columns, types, null %, join hints
dp_describe(con, search = "judge")       # columns by name
```

dbplyr works unchanged:

``` r

library(dplyr)
tbl(con, "proceedings") |>
  select(DEC_CODE) |>
  head(10) |>
  collect()
dp_disconnect(con)
```

## Several databases

Pass a vector of ids. Tables are then qualified by database id, and ids
that contain a hyphen must be double-quoted in SQL:

``` r

con <- dp_connect(c("cms-medicare", "openpayments"))
DBI::dbGetQuery(con, 'SELECT * FROM "cms-medicare".physician_summary LIMIT 5')
tbl(con, I('"openpayments".main.general_payments')) |> head(5) |> collect()
dp_disconnect(con)
```

## Local copies

Remote mode fetches metadata and data ranges over HTTP. Filters, views
and joins can scan much of a file, even when the result is small.
Download once for repeated disk reads:

``` r

dp_download("dol-visas")
con <- dp_connect("dol-visas", local = TRUE)
dp_disconnect(con)      # close the local file before replacing it
dp_update("dol-visas")   # compare with the published remote version
```

File size describes disk storage, not RAM. Allow room for the new file,
temporary download bytes and any existing copy. Close connections to a
local file before updating it, especially on Windows.

Set `options(datapond.data_dir = "~/.datapond")` to share downloads with
the Python package.
