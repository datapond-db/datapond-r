## Test environments

* GitHub Actions: Ubuntu 26.04.1, R 4.6.2, full `R CMD check --as-cran`
  including PDF manual, HTML validation, incoming and suggested-package checks.
* GitHub Actions: ubuntu-latest, macos-latest, windows-latest (R release),
  standard package checks.
* Local: Ubuntu 24.04 (WSL2), R 4.5.3 (conda-forge); code, examples,
  vignettes and tests pass. Local PDF checks could not run without LaTeX;
  the complete release check above passes with TinyTeX installed.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes for CRAN

* CRAN currently lists 0.1.0, published 2026-09-27:
  <https://CRAN.R-project.org/package=datapond>.
* These results are for version 0.1.1, checked November 16, 2026:
  <https://github.com/datapond-db/datapond-r/actions/runs/43973398976>.
* This update fixes download identity, validation, resume and cache handling;
  adds configurable DuckDB resource limits; and expands regression coverage.
* No resubmission has been made yet.
* All examples that reach the network are wrapped in `\dontrun{}`; the
  test suite runs offline against a fixture DuckDB file. The single network
  test is skipped on CRAN (`skip_on_cran()`).
* The package writes only to `tools::R_user_dir("datapond", "cache")` and
  `tools::R_user_dir("datapond", "data")`, and only when the user calls
  `dp_registry()`/`dp_download()`.
