# Fake Zotero (connector + local API). `routes` maps "METHOD path-regex" to a
# response list(status, body, headers); every request is logged.
mock_zotero <- function(routes = list(), env = parent.frame()) {
  log <- new.env()
  log$requests <- list()
  defaults <- list(
    "POST /connector/getSelectedCollection" = list(
      body = '{"libraryName":"My Library","name":"My Library","id":null,"editable":true}'
    ),
    "GET /api/users/0/groups" = list(body = "[]", headers = list(`Zotero-Server-ID` = "SID")),
    "GET /api/users/0/items" = list(body = "[]", headers = list(`Last-Modified-Version` = "7")),
    "POST /connector/import" = list(status = 201L, body = '[{"key":"A"},{"key":"B"}]')
  )
  routes <- c(routes, defaults)
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) {
      method <- req$method %||% if (is.null(req$body)) "GET" else "POST"
      path <- sub("^https?://[^/]+", "", sub("\\?.*$", "", req$url))
      log$requests[[length(log$requests) + 1L]] <- list(method = method, path = path, req = req)
      for (r in names(routes)) {
        if (grepl(paste0("^", r, "$"), paste(method, path))) {
          x <- routes[[r]]
          return(structure(
            list(status = x$status %||% 200L, body = x$body %||% "", headers = x$headers %||% list()),
            class = "fake_resp"
          ))
        }
      }
      stop("unmocked request: ", method, " ", path)
    },
    resp_status = function(resp, ...) resp$status,
    resp_has_body = function(resp, ...) nzchar(resp$body),
    resp_body_string = function(resp, ...) resp$body,
    resp_header = function(resp, header, ...) resp$headers[[header]],
    .package = "httr2",
    .env = env
  )
  log
}

# body sent with a logged request, as text
sent <- function(r) r$req$body$data

csl_files <- function(n = 2L, ids = NULL) {
  d <- tempfile("csl_")
  dir.create(d)
  items <- if (is.null(ids)) {
    '[{"type":"article-journal","title":"a"}]'
  } else {
    jsonlite::toJSON(
      lapply(ids, function(id) list(type = "article-journal", id = paste0("https://openalex.org/", id))),
      auto_unbox = TRUE
    )
  }
  for (i in seq_len(n)) {
    writeLines(items, file.path(d, sprintf("chunk_%d.json", i)))
  }
  d
}

# local API answer listing existing items with "OpenAlex: W..." in Extra
existing_items <- function(...) {
  ids <- c(...)
  jsonlite::toJSON(
    lapply(seq_along(ids), function(i) {
      list(data = list(
        key = paste0("OLD", i), version = 5L, itemType = "journalArticle",
        title = "old title", abstractNote = "old abstract",
        extra = paste0("OpenAlex: ", ids[[i]]), tags = list(list(tag = "mine"))
      ))
    }),
    auto_unbox = TRUE
  )
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
  mock_zotero(list("POST /connector/getSelectedCollection" = list(
    body = '{"libraryName":"Group","name":"Group","id":null,"editable":false}'
  )))
  expect_error(csljson_to_zotero(csl_files()), "read-only")
})

test_that("imports every file of a directory and counts items", {
  log <- mock_zotero()
  expect_message(res <- csljson_to_zotero(csl_files(2L)), "My Library")
  expect_equal(nrow(res), 2L)
  expect_true(all(res$ok))
  expect_equal(res$status_code, c(201L, 201L))
  expect_equal(res$n_items, c(2L, 2L))
  # import is sent as text/plain, or Zotero's translators never see it
  imp <- Filter(function(r) r$path == "/connector/import", log$requests)[[1]]
  expect_equal(imp$req$body$content_type, "text/plain")
})

test_that("records missing, non-JSON and unimportable files", {
  mock_zotero(list("POST /connector/import" = list(status = 400L, body = "")))
  bad <- tempfile(fileext = ".json")
  writeLines("not json", bad)
  res <- suppressMessages(csljson_to_zotero(
    c("nope.json", bad, file.path(csl_files(1L), "chunk_1.json"))
  ))
  expect_false(any(res$ok))
  expect_equal(res$message[1], "File does not exist")
  expect_equal(res$message[2], "Not a JSON file")
  expect_true(all(is.na(res$status_code[1:2])))
  expect_equal(res$status_code[3], 400L)
  expect_match(res$message[3], "no importer")
})

test_that("a group selected in Zotero is addressed as /groups/<id>", {
  log <- mock_zotero(list(
    "POST /connector/getSelectedCollection" = list(
      body = '{"libraryName":"Team","name":"Team","id":null,"editable":true}'
    ),
    "GET /api/users/0/groups" = list(body = '[{"id":42,"data":{"name":"Team"}}]'),
    "GET /api/groups/42/items" = list(body = "[]")
  ))
  suppressMessages(csljson_to_zotero(csl_files(1L)))
  expect_true(any(vapply(log$requests, function(r) r$path == "/api/groups/42/items", NA)))
})

test_that("skip: known OpenAlex IDs are not imported", {
  log <- mock_zotero(list(
    "GET /api/users/0/items" = list(body = existing_items("W1")),
    "POST /connector/import" = list(status = 201L, body = '[{"key":"N"}]')
  ))
  res <- suppressMessages(csljson_to_zotero(csl_files(1L, ids = c("W1", "W2"))))
  expect_equal(res$n_items, 1L)
  expect_equal(res$n_skipped, 1L)
  expect_equal(res$n_updated, 0L)
  imp <- Filter(function(r) r$path == "/connector/import", log$requests)
  expect_length(imp, 1L)
  expect_false(grepl("W1\"", sent(imp[[1]])))
})

test_that("update/overwrite: copy onto the existing item, delete the copy", {
  for (mode in c("update", "overwrite")) {
    log <- mock_zotero(list(
      "GET /api/users/0/items" = list(
        body = existing_items("W1"),
        headers = list(`Last-Modified-Version` = "9")
      ),
      "POST /connector/import" = list(
        status = 201L,
        body = '[{"key":"TMP","version":0,"itemType":"journalArticle","title":"new title","extra":"OpenAlex: W1","tags":[],"collections":["C1"]}]'
      ),
      "POST /api/users/0/items" = list(body = '{"success":{"0":"OLD1"},"unchanged":{},"failed":{}}'),
      "DELETE /api/users/0/items" = list(status = 204L)
    ))
    res <- suppressMessages(csljson_to_zotero(
      csl_files(1L, ids = "W1"), existing = mode, api_key = "KEY"
    ))
    expect_true(res$ok)
    expect_equal(res$n_updated, 1L)
    expect_equal(res$n_items, 0L)

    post <- Filter(function(r) r$method == "POST" && r$path == "/api/users/0/items", log$requests)[[1]]
    upd <- jsonlite::fromJSON(sent(post), simplifyVector = FALSE)[[1]]
    expect_equal(upd$key, "OLD1")
    expect_equal(upd$version, 5L)
    expect_equal(upd$title, "new title")
    expect_null(upd$tags) # old tags and collections stay untouched
    expect_null(upd$collections)
    expect_equal(post$req$headers$`Zotero-API-Key`, "KEY")
    if (mode == "update") {
      expect_null(upd$abstractNote) # kept
    } else {
      expect_equal(upd$abstractNote, "") # emptied
    }

    del <- Filter(function(r) r$method == "DELETE", log$requests)[[1]]
    expect_match(del$req$url, "itemKey=TMP")
    expect_equal(del$req$headers$`If-Unmodified-Since-Version`, "9")
  }
})

test_that("OpenAlex ID is read from Zotero's Extra", {
  expect_equal(.extra_openalex_id("OpenAlex: W123\nOA:TRUE"), "W123")
  expect_equal(.extra_openalex_id("note\nOpenAlex: W9"), "W9")
  expect_true(is.na(.extra_openalex_id(NULL)))
  expect_true(is.na(.extra_openalex_id("no id here")))
})

test_that("all known Extra forms of the OpenAlex ID are read", {
  forms <- c(
    "OpenAlex: W2112574986", # this package, IPBES pipeline
    "OpenAlex: https://openalex.org/W2112574986", # Zotero's OpenAlex translators
    "openalex.work_id: W2112574986", # zotero-openalex plugin
    "OpenAlex Work ID: W2112574986", # open-alex-work-id plugin
    "openalex: https://OpenAlex.org/w2112574986 ", # case, trailing space
    "Citation Key: x\nopenalex.cit_count: 5\nopenalex.work_id: W2112574986"
  )
  for (f in forms) expect_equal(.extra_openalex_id(f), "W2112574986", label = f)

  # not an ID line, or an ID of another entity
  for (f in c("see OpenAlex: W1 in the text", "OpenAlex: A5023888391", "OpenAlex: W12x")) {
    expect_true(is.na(.extra_openalex_id(f)), label = f)
  }
})

test_that("skip recognises items whose Extra uses another form", {
  log <- mock_zotero(list(
    "GET /api/users/0/items" = list(body = jsonlite::toJSON(list(
      list(data = list(key = "K1", version = 1L, extra = "OpenAlex: https://openalex.org/W1")),
      list(data = list(key = "K2", version = 1L, extra = "openalex.work_id: W2")),
      list(data = list(key = "K3", version = 1L, extra = "OpenAlex Work ID: W3"))
    ), auto_unbox = TRUE)),
    "POST /connector/import" = list(status = 201L, body = '[{"key":"N"}]')
  ))
  res <- suppressMessages(csljson_to_zotero(csl_files(1L, ids = c("W1", "W2", "W3", "W4"))))
  expect_equal(res$n_skipped, 3L)
  expect_equal(res$n_items, 1L)
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
