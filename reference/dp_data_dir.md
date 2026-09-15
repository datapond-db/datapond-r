# Local directories used by datapond

The registry is cached under `tools::R_user_dir("datapond", "cache")`
and downloaded databases live under
`tools::R_user_dir("datapond", "data")`. Override either with
`options(datapond.cache_dir = ...)` /
`options(datapond.data_dir = ...)`. Setting
`options(datapond.data_dir = "~/.datapond")` shares downloads with the
Python package, which names local files the same way (`<id>.duckdb`).

## Usage

``` r
dp_data_dir()

dp_cache_dir()
```

## Value

A path (character scalar).

## Examples

``` r
dp_data_dir()
#> [1] "/home/runner/.local/share/R/datapond"
```
