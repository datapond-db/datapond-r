## Test environments

* local: Ubuntu 24.04 (WSL2), R 4.5.x (conda-forge), `R CMD check --as-cran`
* GitHub Actions: ubuntu-latest, macos-latest, windows-latest (R release)

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes for CRAN

* This is a new submission.
* All examples that reach the network are wrapped in `\dontrun{}`; the
  test suite runs offline against a fixture DuckDB file. The single network
  test is skipped on CRAN (`skip_on_cran()`).
* The package writes only to `tools::R_user_dir("datapond", "cache")` and
  `tools::R_user_dir("datapond", "data")`, and only when the user calls
  `dp_registry()`/`dp_download()`.
