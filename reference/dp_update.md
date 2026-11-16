# Update a local database if the remote file has changed

Compares the identity of the remote file (ETag, else Last-Modified, from
a HEAD request) with the one recorded when the local copy was
downloaded, and re-downloads when they differ or when the revision
cannot be verified. Copies without a usable identity record are
re-downloaded when update is requested; local modification times and
registry dates cannot prove which bytes they contain. The registry is
re-fetched first.

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
