test_that("dp_describe reads _metadata and _columns", {
  local_datapond()
  tables <- dp_describe("testdb")
  expect_equal(tables$table_name, c("cases", "lu_nationality"))
  expect_equal(tables$row_count, c(3, 2))

  cols <- dp_describe("testdb", table = "cases")
  expect_equal(cols$column_name, c("IDNCASE", "NAT", "filed"))
  expect_equal(cols$join_hint[2], "Joins to lu_nationality.NAT_CODE")
  expect_equal(cols$null_pct[2], 33.3)

  hits <- dp_describe("testdb", search = "nat")
  expect_setequal(hits$column_name, c("NAT", "NAT_CODE", "NAT_NAME"))
})

test_that("dp_describe accepts an open connection", {
  local_datapond()
  con <- dp_connect("testdb", quiet = TRUE)
  on.exit(dp_disconnect(con))
  expect_equal(nrow(dp_describe(con)), 2L)
  expect_equal(nrow(dp_describe(con, table = "lu_nationality")), 2L)
})

test_that("dp_describe falls back to information_schema without a dictionary", {
  local_datapond(with_dictionary = FALSE)
  tables <- dp_describe("testdb")
  expect_setequal(tables$table_name, c("cases", "lu_nationality"))
  expect_true(all(is.na(tables$row_count)))
  cols <- dp_describe("testdb", table = "cases")
  expect_equal(cols$column_name, c("IDNCASE", "NAT", "filed"))
  expect_true(all(is.na(cols$join_hint)))
  expect_equal(dp_describe("testdb", search = "idn")$column_name, "IDNCASE")
})
