# Explore a database's data dictionary

Every datapond database ships `_metadata` (one row per table) and
`_columns` (types, null rates, example values, join hints).
`dp_describe()` reads them and falls back to `information_schema` when
they are absent.

## Usage

``` r
dp_describe(x, table = NULL, search = NULL)
```

## Arguments

- x:

  A database id, or an open connection from
  [`dp_connect()`](https://datapond-db.github.io/datapond-r/reference/dp_connect.md).

- table:

  Describe the columns of this table instead of listing tables.

- search:

  Find columns whose name contains this text (case-insensitive).

## Value

A data frame (a tibble when the tibble package is installed).

## Examples

``` r
if (FALSE) { # \dontrun{
dp_describe("eoir")
dp_describe("eoir", table = "proceedings")
dp_describe("eoir", search = "judge")
} # }
```
