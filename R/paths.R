#' Local directories used by datapond
#'
#' The registry is cached under `tools::R_user_dir("datapond", "cache")` and
#' downloaded databases live under `tools::R_user_dir("datapond", "data")`.
#' Override either with `options(datapond.cache_dir = ...)` /
#' `options(datapond.data_dir = ...)`. Setting
#' `options(datapond.data_dir = "~/.datapond")` shares downloads with the
#' Python package, which names local files the same way (`<id>.duckdb`).
#'
#' @return A path (character scalar).
#' @export
#' @examples
#' dp_data_dir()
dp_data_dir <- function() {
  getOption("datapond.data_dir", tools::R_user_dir("datapond", "data"))
}

#' @rdname dp_data_dir
#' @export
dp_cache_dir <- function() {
  getOption("datapond.cache_dir", tools::R_user_dir("datapond", "cache"))
}

#' Path of a locally downloaded database
#'
#' @param id Database id (see [dp_list()]).
#' @param must_exist Error if the file is not present?
#' @return A path (character scalar).
#' @export
#' @examples
#' dp_local_path("eoir")
dp_local_path <- function(id, must_exist = FALSE) {
  stopifnot(is.character(id), length(id) == 1L)
  path <- file.path(dp_data_dir(), paste0(id, ".duckdb"))
  if (must_exist && !file.exists(path)) {
    stop(sprintf("No local copy of '%s' at %s. Download it first with dp_download('%s').",
                 id, path, id), call. = FALSE)
  }
  path
}
