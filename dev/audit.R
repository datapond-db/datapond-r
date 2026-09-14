# Thorough live audit of the datapond R package against every registry database.
# Run: conda run -n datapond-r --no-capture-output Rscript dev/audit.R
suppressPackageStartupMessages({
  library(datapond)
  library(DBI)
})
has_dplyr <- requireNamespace("dplyr", quietly = TRUE) && requireNamespace("dbplyr", quietly = TRUE)

results <- list()
check <- function(id, name, expr) {
  t0 <- Sys.time()
  out <- tryCatch({
    v <- force(expr)
    if (length(v) == 0) v <- "<empty>"
    list(ok = isTRUE(v) || (is.numeric(v) && length(v) == 1 && !is.na(v) && v > 0), value = v)
  }, error = function(e) list(ok = FALSE, value = conditionMessage(e)))
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  results[[length(results) + 1]] <<- data.frame(
    id = id, check = name, ok = out$ok, secs = secs,
    detail = substr(paste(format(out$value), collapse = " "), 1, 80),
    stringsAsFactors = FALSE)
  cat(sprintf("  [%s] %-42s %6.1fs  %s\n", if (out$ok) "PASS" else "FAIL", name, secs,
              substr(paste(format(out$value), collapse = " "), 1, 60)))
  invisible(out)
}

cat("== registry ==\n")
invisible(dp_registry(refresh = TRUE))
ids <- dp_list()
check("registry", "dp_list returns >= 8 ids", length(ids) >= 8)
dbs <- dp_databases()
check("registry", "dp_databases has one row per id", nrow(dbs) == length(ids))
check("registry", "dp_databases rows/size numeric", is.numeric(dbs$rows) && is.numeric(dbs$size_gb))
check("registry", "registry cache written", file.exists(file.path(dp_cache_dir(), "registry.json")))
check("registry", "unknown id errors clearly",
      tryCatch({dp_info("nope"); FALSE}, error = function(e) grepl("Available:", conditionMessage(e))))

for (id in ids) {
  cat(sprintf("\n== %s ==\n", id))
  info <- check(id, "dp_info", inherits(dp_info(id), "datapond_db"))
  con <- tryCatch(dp_connect(id, quiet = TRUE), error = function(e) NULL)
  check(id, "dp_connect (remote)", !is.null(con))
  if (is.null(con)) next
  tabs <- check(id, "dp_describe(): tables listed", nrow(dp_describe(con)))
  meta <- dp_describe(con)
  check(id, "_metadata row_count populated", all(!is.na(meta$row_count)) && sum(meta$row_count) > 0)
  check(id, "registry rows match _metadata sum",
        abs(sum(meta$row_count) - dp_info(id)$rows) / dp_info(id)$rows < 0.005)
  first <- meta$table_name[which.max(meta$row_count)]
  cols <- check(id, sprintf("dp_describe(table = '%s')", first), nrow(dp_describe(con, table = first)))
  cdf <- dp_describe(con, table = first)
  check(id, "column dictionary has null_pct/join_hint", all(c("null_pct", "join_hint") %in% names(cdf)))
  check(id, "dp_describe(search = 'id') finds columns", nrow(dp_describe(con, search = "id")))
  q <- DBI::dbQuoteIdentifier(con, first)
  check(id, sprintf("SELECT * FROM %s LIMIT 5", first), nrow(dbGetQuery(con, paste("SELECT * FROM", q, "LIMIT 5"))))
  check(id, "COUNT(*) on largest table equals _metadata",
        dbGetQuery(con, paste("SELECT count(*) AS n FROM", q))$n == meta$row_count[meta$table_name == first])
  check(id, "dbListTables works", length(dbListTables(con)) > 0)
  if (has_dplyr) {
    check(id, "dbplyr tbl() |> head() |> collect()",
          nrow(dplyr::collect(head(dplyr::tbl(con, first), 3))))
  }
  dp_disconnect(con)
  check(id, "dp_disconnect", TRUE)
}

cat("\n== multi-database ==\n")
con <- dp_connect(c("cms-medicare", "openpayments"), quiet = TRUE)
check("multi", "hyphenated catalog is queryable",
      dbGetQuery(con, 'SELECT count(*) AS n FROM "cms-medicare".physician_summary')$n)
check("multi", "unqualified table errors (no USE with 2 ids)",
      tryCatch({dbGetQuery(con, "SELECT count(*) FROM physician_summary"); FALSE}, error = function(e) TRUE))
check("multi", "cross-database NPI join runs",
      dbGetQuery(con, paste(
        'SELECT count(*) AS n FROM (SELECT Rndrng_NPI FROM "cms-medicare".physician_summary WHERE year = 2024 LIMIT 2000) m',
        'JOIN (SELECT DISTINCT covered_recipient_npi FROM openpayments.general_payments WHERE program_year = 2025 LIMIT 200000) o',
        'ON m.Rndrng_NPI = o.covered_recipient_npi'))$n >= 0)
if (has_dplyr) {
  check("multi", "dbplyr I() reference to hyphenated catalog",
        nrow(dplyr::collect(head(dplyr::tbl(con, I('"cms-medicare".main.physician_summary')), 2))))
}
dp_disconnect(con)

cat("\n== local download (smallest database) ==\n")
small <- dbs$id[which.min(dbs$size_gb)]
withr::local_options(datapond.data_dir = tempfile("dp-audit-"))
check("local", sprintf("dp_download('%s')", small), file.exists(dp_download(small, quiet = TRUE)))
check("local", "dp_update reports up to date",
      tryCatch({msgs <- character(); withCallingHandlers(dp_update(small), message = function(m) {msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage")}); any(grepl("up to date", msgs))}, error = function(e) FALSE))
con <- dp_connect(small, local = TRUE, quiet = TRUE)
check("local", "local connect + count", dbGetQuery(con, paste("SELECT count(*) AS n FROM", DBI::dbQuoteIdentifier(con, dp_describe(con)$table_name[1])))$n)
dp_disconnect(con)

res <- do.call(rbind, results)
cat(sprintf("\n== SUMMARY: %d checks, %d failed ==\n", nrow(res), sum(!res$ok)))
print(res[!res$ok, c("id", "check", "detail")], row.names = FALSE)
write.csv(res, "dev/audit_results.csv", row.names = FALSE)
if (any(!res$ok)) quit(status = 1)
