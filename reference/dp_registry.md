# The datapond registry

Fetches `registry.json` from GitHub (cached for an hour under
[`dp_cache_dir()`](https://datapond-db.github.io/datapond-r/reference/dp_data_dir.md);
a stale cache is used if the network is unavailable).

## Usage

``` r
dp_registry(refresh = FALSE)
```

## Arguments

- refresh:

  Ignore the cache and fetch again?

## Value

The parsed registry: a list with a `databases` element, one list per
database.

## Examples

``` r
if (FALSE) { # \dontrun{
reg <- dp_registry()
length(reg$databases)
} # }
```
