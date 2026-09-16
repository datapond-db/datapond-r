# Update a local database if the remote file has changed

Compares the identity of the remote file (ETag and size, from a HEAD
request) with the one recorded when the local copy was downloaded, and
re-downloads when they differ. Copies without that record fall back to
the registry's `updated` date versus the file's modification time and
are re-downloaded whenever that comparison is inconclusive. The registry
is re-fetched first.

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
