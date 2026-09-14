# Offline fixtures: a tiny DuckDB file with the canonical datapond metadata
# tables, and a registry JSON whose attach_url points at that file. Because the
# attach_url is a local path, dp_connect() exercises quoting, USE, and the
# _metadata/_columns readers without httpfs or the network.

make_fixture_db <- function(path, with_dictionary = TRUE) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE cases (IDNCASE INTEGER, NAT VARCHAR, filed DATE)")
  DBI::dbExecute(con, "INSERT INTO cases VALUES (1,'MX','2020-01-01'),(2,'GT',NULL),(3,NULL,'2021-05-05')")
  DBI::dbExecute(con, "CREATE TABLE lu_nationality (NAT_CODE VARCHAR, NAT_NAME VARCHAR)")
  DBI::dbExecute(con, "INSERT INTO lu_nationality VALUES ('MX','Mexico'),('GT','Guatemala')")
  if (with_dictionary) {
    DBI::dbExecute(con, paste(
      "CREATE TABLE _metadata (table_name VARCHAR, description VARCHAR, row_count BIGINT,",
      "column_count INTEGER, source_url VARCHAR, license VARCHAR)"))
    DBI::dbExecute(con, paste(
      "INSERT INTO _metadata VALUES ('cases','Court cases',3,3,NULL,NULL),",
      "('lu_nationality','Nationality lookup',2,2,NULL,NULL)"))
    DBI::dbExecute(con, paste(
      "CREATE TABLE _columns (table_name VARCHAR, column_name VARCHAR, data_type VARCHAR,",
      "source_file VARCHAR, example_value VARCHAR, join_hint VARCHAR, null_pct DOUBLE)"))
    DBI::dbExecute(con, paste(
      "INSERT INTO _columns VALUES",
      "('cases','IDNCASE','INTEGER',NULL,'1','Primary case ID',0.0),",
      "('cases','NAT','VARCHAR',NULL,'MX','Joins to lu_nationality.NAT_CODE',33.3),",
      "('cases','filed','DATE',NULL,'2020-01-01',NULL,33.3),",
      "('lu_nationality','NAT_CODE','VARCHAR',NULL,'MX',NULL,0.0),",
      "('lu_nationality','NAT_NAME','VARCHAR',NULL,'Mexico',NULL,0.0)"))
  }
  path
}

local_datapond <- function(with_dictionary = TRUE, env = parent.frame()) {
  tmp <- withr::local_tempdir(.local_envir = env)
  withr::local_options(
    datapond.cache_dir = file.path(tmp, "cache"),
    datapond.data_dir = file.path(tmp, "data"),
    .local_envir = env)
  db <- make_fixture_db(file.path(tmp, "fixture.duckdb"), with_dictionary = with_dictionary)
  reg <- list(databases = list(
    list(id = "testdb", name = "Test DB", rows = 5L, tables = 2L, size_gb = 0.001,
         source = "fixture", attach_url = db, updated = "2026-01-01"),
    list(id = "test-hyphen", name = "Hyphen DB", rows = 5L, tables = 2L, size_gb = 0.001,
         source = "fixture", attach_url = db, updated = "2026-01-01")))
  regfile <- file.path(tmp, "registry.json")
  jsonlite::write_json(reg, regfile, auto_unbox = TRUE)
  withr::local_options(datapond.registry_url = regfile, .local_envir = env)
  invisible(list(db = db, root = tmp, registry = regfile))
}
