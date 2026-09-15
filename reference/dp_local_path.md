# Path of a locally downloaded database

Path of a locally downloaded database

## Usage

``` r
dp_local_path(id, must_exist = FALSE)
```

## Arguments

- id:

  Database id (see
  [`dp_list()`](https://datapond-db.github.io/datapond-r/reference/dp_list.md)).

- must_exist:

  Error if the file is not present?

## Value

A path (character scalar).

## Examples

``` r
dp_local_path("eoir")
#> [1] "/home/runner/.local/share/R/datapond/eoir.duckdb"
```
