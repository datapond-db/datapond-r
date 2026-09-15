# Update a local database if the registry has a newer version

Compares the registry's `updated` date with the local file's
modification time and re-downloads when the registry is newer.

## Usage

``` r
dp_update(id, quiet = FALSE)
```

## Arguments

- id:

  Database id.

- quiet:

  Suppress the progress bar?

## Value

The local path, invisibly.
