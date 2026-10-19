# datapond (R)

**Public data, instantly queryable.**

R client for the [datapond](https://datapond-db.github.io/website/) registry of
curated DuckDB databases built from public government and research data:
immigration, courts and judges, campaign finance, health, education, occupations,
employment and fatal crashes. No full download is required first and no API key
is needed: DuckDB reads ranges over HTTP and executes queries on your machine.

The Python equivalent is [`datapond` on PyPI](https://pypi.org/project/datapond/).

## Install

Install the released package from [CRAN](https://CRAN.R-project.org/package=datapond):

```r
install.packages("datapond")
```

CRAN version **0.1.0** was published on September 27, 2026. The development
version **0.1.1** in this repository includes additional download fixes and
resource controls that are not yet on CRAN. To use that version:

```r
# install.packages("pak")
pak::pak("datapond-db/datapond-r")
```

See the [CRAN check results](https://cran.r-project.org/web/checks/check_results_datapond.html)
and [development changes](NEWS.md).

## Quick start

```r
library(datapond)

dp_list()                 # database ids
dp_info("eoir")           # size, source, coverage, links

con <- dp_connect("eoir") # attaches over HTTP; no full download required first
DBI::dbGetQuery(con, "SELECT * FROM proceedings LIMIT 5")

dp_describe(con)                         # tables with row counts
dp_describe(con, table = "proceedings")  # columns, types, null %, join hints
dp_describe(con, search = "judge")       # find columns by name

dp_disconnect(con)
```

The connection is a plain `duckdb_connection`, so `DBI` and `dbplyr` work as usual:

```r
library(dplyr)
con <- dp_connect("eoir")
tbl(con, "proceedings") |> select(DEC_CODE) |> head(10) |> collect()
dp_disconnect(con)
```

## Several databases at once

```r
library(datapond)
library(dplyr)
con <- dp_connect(c("cms-medicare", "openpayments"))
# Tables are qualified by database id; ids with a hyphen need double quotes.
# With dbplyr, I() preserves the explicitly quoted catalog and schema name.
DBI::dbGetQuery(con, 'SELECT * FROM "cms-medicare".physician_summary LIMIT 5')
tbl(con, I('"openpayments".main.general_payments')) |> head(5) |> collect()
dp_disconnect(con)
```

## Bound query resources

For released CRAN 0.1.0, set limits immediately after attachment and before a query:

```r
con <- datapond::dp_connect("onet")
DBI::dbExecute(con, "SET memory_limit='128MiB'; SET threads=1; SET max_temp_directory_size='0B'")
DBI::dbGetQuery(con, "SELECT onet_soc_code, title FROM occupation_data ORDER BY onet_soc_code LIMIT 5")
datapond::dp_disconnect(con)
```

These limits cover DuckDB's buffer pool, not all R allocations. With spill disabled, larger queries can fail. In development 0.1.1, pass settings before remote attachment:

```r
con <- dp_connect("eoir", config = list(
  memory_limit = "1GB", threads = "2",
  temp_directory = tempfile("datapond-spill-"),
  max_temp_directory_size = "2GB"
))
# Filter and aggregate in SQL before collecting results into R.
dp_disconnect(con)
```

Set `options(datapond.duckdb_config = list(...))` to use the same settings for
later connections. DuckDB's memory limit does not cover all R allocations;
leave desktop headroom and enough disk space for spill files and downloads.
CRAN 0.1.0 users can set DuckDB resource settings with `DBI::dbExecute()` after
connecting, or install the development version for configuration at startup.

## Local copies

Remote queries fetch metadata and data ranges over HTTP. A simple base-table count may use metadata, but filters, views and joins can scan much of a file. A small result or a final `LIMIT` does not guarantee a small transfer. Download once for repeated disk reads:

```r
dp_download("dol-visas")                     # to dp_data_dir()
con <- dp_connect("dol-visas", local = TRUE)
dp_disconnect(con)                          # close the local file before replacing it
dp_update("dol-visas")                       # compare with the published remote version
```

File size describes disk storage, not RAM. Allow room for the new file, temporary download bytes and any existing copy. Close connections to a local file before updating it, especially on Windows.

Set `options(datapond.data_dir = "~/.datapond")` to share downloads with the
Python package.

## Credits

datapond is built and maintained by [Ian Nason](https://github.com/ian-nason).
The IPEDS database is by [Paul Goldsmith-Pinkham](https://github.com/paulgp).
See the [registry](https://github.com/datapond-db/registry#contributors).

## License

MIT
