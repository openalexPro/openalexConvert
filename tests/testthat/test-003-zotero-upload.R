test_that("csljson_to_zotero_upload errors on empty api key", {
  expect_error(
    csljson_to_zotero_upload(
      files = "x.json",
      group_id = "123",
      api_key = ""
    ),
    "API key is empty"
  )
})

test_that("csljson_to_zotero_upload errors when no files are supplied", {
  empty_dir <- tempfile("empty_")
  dir.create(empty_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(empty_dir, recursive = TRUE, force = TRUE), add = TRUE)
  expect_error(
    csljson_to_zotero_upload(
      files = empty_dir,
      group_id = "123",
      api_key = "dummy"
    )
  )
})

test_that("csljson_to_zotero_upload records missing files without network", {
  res <- csljson_to_zotero_upload(
    files = c("nope-1.json", "nope-2.json"),
    group_id = "123",
    api_key = "dummy",
    pause = 0
  )
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 2L)
  expect_false(any(res$ok))
  expect_true(all(is.na(res$status_code)))
  expect_true(all(res$message == "File does not exist"))
})

test_that("csljson_to_zotero_upload success path (mocked httr2)", {
  skip_if_not_installed("httr2")

  d <- tempfile("csl_")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE, force = TRUE), add = TRUE)
  writeLines('[{"type":"article","title":"a"}]', file.path(d, "a.json"))
  writeLines('[{"type":"article","title":"b"}]', file.path(d, "b.json"))

  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "fake_resp"),
    resp_status = function(resp, ...) 200L,
    .package = "httr2"
  )

  res <- csljson_to_zotero_upload(
    files = d,
    group_id = "123",
    api_key = "dummy",
    pause = 0
  )
  expect_equal(nrow(res), 2L)
  expect_true(all(res$ok))
  expect_true(all(res$status_code == 200L))
})

test_that("csljson_to_zotero_upload failure path captures body (mocked)", {
  skip_if_not_installed("httr2")

  f <- tempfile(fileext = ".json")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  writeLines('[{"type":"article","title":"a"}]', f)

  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "fake_resp"),
    resp_status = function(resp, ...) 400L,
    resp_body_string = function(resp, ...) "Bad Request: invalid item",
    .package = "httr2"
  )

  res <- csljson_to_zotero_upload(
    files = f,
    group_id = "123",
    api_key = "dummy",
    pause = 0
  )
  expect_equal(nrow(res), 1L)
  expect_false(res$ok)
  expect_equal(res$status_code, 400L)
  expect_match(res$message, "Bad Request")
})

test_that("csljson_to_zotero_upload captures request errors (mocked)", {
  skip_if_not_installed("httr2")

  f <- tempfile(fileext = ".json")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  writeLines('[{"type":"article","title":"a"}]', f)

  testthat::local_mocked_bindings(
    req_perform = function(req, ...) stop("connection refused"),
    .package = "httr2"
  )

  res <- csljson_to_zotero_upload(
    files = f,
    group_id = "123",
    api_key = "dummy",
    pause = 0
  )
  expect_false(res$ok)
  expect_true(is.na(res$status_code))
  expect_match(res$message, "connection refused")
})
