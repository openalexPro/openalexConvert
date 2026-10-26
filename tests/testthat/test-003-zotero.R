# Fake Zotero connector: answers getSelectedCollection with `target` and
# every import with `status` / `body`.
mock_zotero <- function(
  status = 201L,
  body = '[{"key":"A"},{"key":"B"}]',
  target = '{"libraryName":"My Library","name":"My Library","id":null,"editable":true}',
  env = parent.frame()
) {
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) {
      if (grepl("getSelectedCollection", req$url)) {
        structure(list(body = target, status = 200L), class = "fake_resp")
      } else {
        structure(list(body = body, status = status), class = "fake_resp")
      }
    },
    resp_status = function(resp, ...) resp$status,
    resp_has_body = function(resp, ...) nzchar(resp$body),
    resp_body_string = function(resp, ...) resp$body,
    .package = "httr2",
    .env = env
  )
}

csl_files <- function(n = 2L) {
  d <- tempfile("csl_")
  dir.create(d)
  for (i in seq_len(n)) {
    writeLines('[{"type":"article-journal","title":"a"}]', file.path(d, sprintf("chunk_%d.json", i)))
  }
  d
}

test_that("method = 'web' is not implemented yet", {
  expect_error(csljson_to_zotero("x.json", method = "web"), "not implemented yet")
})

test_that("errors when no files are supplied", {
  expect_error(csljson_to_zotero(csl_files(0L)))
})

test_that("errors when Zotero is not running", {
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) stop("connection refused"),
    .package = "httr2"
  )
  expect_error(csljson_to_zotero(csl_files()), "Is the Zotero desktop app running")
})

test_that("errors when the selected Zotero target is read-only", {
  mock_zotero(target = '{"libraryName":"Group","name":"Group","id":null,"editable":false}')
  expect_error(csljson_to_zotero(csl_files()), "read-only")
})

test_that("imports every file of a directory and counts items", {
  mock_zotero()
  expect_message(res <- csljson_to_zotero(csl_files(2L)), "My Library")
  expect_equal(nrow(res), 2L)
  expect_true(all(res$ok))
  expect_equal(res$status_code, c(201L, 201L))
  expect_equal(res$n_items, c(2L, 2L))
})

test_that("records missing files and unimportable files", {
  mock_zotero(status = 400L, body = "")
  res <- suppressMessages(csljson_to_zotero(c("nope.json", file.path(csl_files(1L), "chunk_1.json"))))
  expect_false(any(res$ok))
  expect_equal(res$message[1], "File does not exist")
  expect_true(is.na(res$status_code[1]))
  expect_equal(res$status_code[2], 400L)
  expect_match(res$message[2], "no importer")
})

test_that("CSL note starts with the OpenAlex id line (Zotero Extra)", {
  out <- tempfile("csl_")
  corpus_to_csljson(
    corpus = testthat::test_path("..", "fixtures", "corpus"),
    output = out,
    verbose = FALSE
  )
  items <- unlist(
    lapply(list.files(out, full.names = TRUE), jsonlite::read_json),
    recursive = FALSE
  )
  ids <- sub("^https://openalex.org/", "", vapply(items, `[[`, "", "id"))
  notes <- vapply(items, `[[`, "", "note")
  expect_true(all(startsWith(notes, paste0("OpenAlex: ", ids))))
  # the newline survives sanitizing; the OA/citation line follows
  expect_match(notes[[1]], "^OpenAlex: W\\d+\nOA:")
})
