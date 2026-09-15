# datapond (R)

**Public data, instantly queryable.**

R client for the [datapond](https://datapond-db.github.io/website/) registry of
curated DuckDB databases built from public government and research data:
immigration courts, ICE enforcement, campaign finance, clinical trials, Medicare
billing, industry payments, visa disclosures, and higher education. No full
download, no API keys: DuckDB attaches the remote file over HTTP and fetches
only the byte ranges your query touches.

The Python equivalent is [`datapond` on PyPI](https://pypi.org/project/datapond/).

## Install

```r
# install.packages("pak")
pak::pak("datapond-db/datapond-r")
```

## Quick start

```r
library(datapond)

dp_list()                 # database ids
dp_info("eoir")           # size, source, coverage, links

con <- dp_connect("eoir") # attaches remotely; nothing is downloaded in full
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
tbl(con, "proceedings") |> count(DEC_CODE, sort = TRUE) |> head(10) |> collect()
```

## Several databases at once

```r
con <- dp_connect(c("cms-medicare", "openpayments"))
# Tables are qualified by database id; ids with a hyphen need double quotes.
# With dbplyr, pass the qualified name through I() (in_catalog() does not accept hyphens).
DBI::dbGetQuery(con, 'SELECT * FROM "cms-medicare".physician_summary LIMIT 5')
tbl(con, I('"openpayments".main.general_payments')) |> head(5) |> collect()
```

## Local copies

Remote queries transfer the byte ranges they touch, which is cheap for counts and
filters but not for `SELECT *` over a 37 GB table. Download once for disk speed:

```r
dp_download("dol-visas")                     # to dp_data_dir()
con <- dp_connect("dol-visas", local = TRUE)
dp_update("dol-visas")                       # re-download if the registry is newer
```

Set `options(datapond.data_dir = "~/.datapond")` to share downloads with the
Python package.

## Credits

datapond is built and maintained by [Ian Nason](https://github.com/ian-nason).
The IPEDS database is by [Paul Goldsmith-Pinkham](https://github.com/paulgp).
See the [registry](https://github.com/datapond-db/registry#contributors).

## License

MIT
