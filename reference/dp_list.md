# List available databases

List available databases

## Usage

``` r
dp_list()

dp_databases()
```

## Value

`dp_list()` returns a character vector of database ids; `dp_databases()`
returns one row per database with its registry fields.

## Examples

``` r
if (FALSE) { # \dontrun{
dp_list()
dp_databases()[, c("id", "rows", "size_gb")]
} # }
```
