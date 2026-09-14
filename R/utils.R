`%||%` <- function(x, y) if (is.null(x)) y else x

as_tbl <- function(df) {
  if (requireNamespace("tibble", quietly = TRUE)) tibble::as_tibble(df) else df
}

fmt_rows <- function(n) {
  if (is.null(n) || is.na(n)) return("?")
  if (n >= 1e9) sprintf("%.1fB", n / 1e9)
  else if (n >= 1e6) sprintf("%.1fM", n / 1e6)
  else if (n >= 1e3) sprintf("%.1fK", n / 1e3)
  else as.character(n)
}

is_url <- function(x) grepl("^https?://", x)
