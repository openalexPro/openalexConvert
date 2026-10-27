# Fake Zotero (connector + local API). `routes` maps "METHOD path-regex" to a
# response list(status, body, headers), or a function(req) returning one;
# every request is logged.
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
          if (is.function(x)) x <- x(req)
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

# local API answer: items with Extra and tags
tagged_items <- function(...) {
  jsonlite::toJSON(list(...), auto_unbox = TRUE)
}

test_that("zotero_tags writes one row per item and tag", {
  mock_zotero(list("GET /api/users/0/items" = list(body = tagged_items(
    list(data = list(key = "K1", extra = "OpenAlex: W1", tags = list(
      list(tag = "include"), list(tag = "Ecology", type = 1L)
    ))),
    list(data = list(key = "K2", extra = "openalex.work_id: W2", tags = list())),
    list(data = list(key = "K3", extra = "no id", tags = list(list(tag = "lost"))))
  ))))
  out <- tempfile(fileext = ".parquet")
  expect_message(tags <- zotero_tags(output = out), "2 tag\\(s\\) on 1 work")
  expect_equal(tags$openalex_id, c("W1", "W1"))
  expect_equal(tags$tag, c("include", "Ecology"))
  expect_equal(tags$type, c(0L, 1L))
  expect_equal(tags$zotero_library, c(0L, 0L))
  expect_equal(tags$zotero_key, c("K1", "K1"))
  expect_equal(as.data.frame(arrow::read_parquet(out)), tags)
})

test_that("zotero_tags replaces this library's rows, keeps other libraries", {
  out <- tempfile(fileext = ".parquet")
  item <- function(tag) {
    tagged_items(list(data = list(key = "K", extra = "OpenAlex: W1", tags = list(list(tag = tag)))))
  }
  mock_zotero(list("GET /api/users/0/items" = list(body = item("old"))))
  suppressMessages(zotero_tags(output = out))
  mock_zotero(list(
    "POST /connector/getSelectedCollection" = list(
      body = '{"libraryName":"Team","name":"Team","id":null,"editable":false}'
    ),
    "GET /api/users/0/groups" = list(body = '[{"id":42,"data":{"name":"Team"}}]'),
    "GET /api/groups/42/items" = list(body = item("group"))
  ))
  suppressMessages(zotero_tags(output = out))
  mock_zotero(list("GET /api/users/0/items" = list(body = item("new"))))
  suppressMessages(zotero_tags(output = out))

  res <- as.data.frame(arrow::read_parquet(out))
  expect_equal(res$tag[order(res$zotero_library)], c("new", "group"))
  expect_setequal(res$zotero_library, c(0L, 42L))
})

test_that("zotero_tags writes an empty table when nothing is tagged", {
  mock_zotero()
  out <- tempfile(fileext = ".parquet")
  tags <- suppressMessages(zotero_tags(output = out))
  expect_equal(nrow(arrow::read_parquet(out)), 0L)
  expect_named(tags, c("openalex_id", "tag", "type", "zotero_library", "zotero_key"))
})

test_that("corpus_to_zotero sends the corpus in chunks and cleans up", {
  log <- mock_zotero()
  before <- list.files(tempdir(), pattern = "^csljson_")
  res <- suppressMessages(corpus_to_zotero(
    corpus = testthat::test_path("..", "fixtures", "corpus"),
    chunk_size = 200,
    collection = NULL
  ))
  expect_equal(nrow(res), 2L) # 369 works
  expect_true(all(res$ok))
  imp <- Filter(function(r) r$path == "/connector/import", log$requests)
  ids <- unlist(lapply(imp, function(r) {
    vapply(jsonlite::fromJSON(sent(r), simplifyVector = FALSE), `[[`, "", "id")
  }))
  expect_length(unique(ids), 369L)
  expect_setequal(list.files(tempdir(), pattern = "^csljson_"), before)
})

# POST /items requests sent, as parsed objects
posted <- function(log) {
  unlist(lapply(
    Filter(function(r) r$method == "POST" && grepl("/items$", r$path), log$requests),
    function(r) jsonlite::fromJSON(sent(r), simplifyVector = FALSE)
  ), recursive = FALSE)
}

test_that("tags: one per work, manual wins over automatic", {
  idx <- .tag_index(data.frame(
    openalex_id = c("W1", "W1", "W1", "w2", "W3"),
    tag = c("a", "b", "a", "c", ""),
    type = c(1L, 1L, 0L, 0L, 0L)
  ))
  expect_named(idx, c("W1", "W2"))
  expect_equal(idx$W1, list(list(tag = "a"), list(tag = "b", type = 1L)))
  expect_equal(idx$W2, list(list(tag = "c")))
})

test_that("tags: new items get the tags of their OpenAlex ID", {
  log <- mock_zotero(list(
    "GET /api/users/0/items" = function(req) {
      list(body = if (grepl("itemKey=N1", req$url)) {
        '[{"data":{"key":"N1","version":3}}]'
      } else {
        "[]"
      })
    },
    "POST /connector/import" = list(
      status = 201L,
      body = '[{"key":"N1","extra":"OpenAlex: W1"},{"key":"N2","extra":"OpenAlex: W2"}]'
    ),
    "POST /api/users/0/items" = list(body = '{"success":{"0":"N1"},"unchanged":{},"failed":{}}')
  ))
  tags <- data.frame(openalex_id = "W1", tag = c("a", "b"), type = c(0L, 1L))
  res <- suppressMessages(csljson_to_zotero(
    csl_files(1L, ids = c("W1", "W2")), tags = tags, api_key = "KEY"
  ))
  expect_true(res$ok)
  expect_equal(res$n_items, 2L)
  expect_equal(res$n_tagged, 1L)
  p <- posted(log)
  expect_length(p, 1L)
  expect_equal(p[[1]], list(key = "N1", version = 3L, tags = list(
    list(tag = "a"), list(tag = "b", type = 1L)
  )))
})

test_that("tags: skip leaves existing items alone", {
  log <- mock_zotero(list("GET /api/users/0/items" = list(body = existing_items("W1"))))
  res <- suppressMessages(csljson_to_zotero(
    csl_files(1L, ids = "W1"),
    tags = data.frame(openalex_id = "W1", tag = "new"), api_key = "KEY"
  ))
  expect_equal(res$n_skipped, 1L)
  expect_equal(res$n_tagged, 0L)
  expect_length(posted(log), 0L)
})

test_that("tags: update adds missing tags, overwrite replaces them", {
  run <- function(mode, tags) {
    log <- mock_zotero(list(
      "GET /api/users/0/items" = list(body = existing_items("W1")),
      "POST /connector/import" = list(
        status = 201L, body = '[{"key":"TMP","title":"t","extra":"OpenAlex: W1"}]'
      ),
      "POST /api/users/0/items" = list(body = '{"success":{"0":"OLD1"},"unchanged":{},"failed":{}}'),
      "DELETE /api/users/0/items" = list(status = 204L)
    ))
    res <- suppressMessages(csljson_to_zotero(
      csl_files(1L, ids = "W1"), existing = mode, tags = tags, api_key = "KEY"
    ))
    list(res = res, upd = posted(log)[[1]])
  }
  tags <- data.frame(openalex_id = "W1", tag = c("mine", "new"))

  u <- run("update", tags) # old item is tagged "mine"
  expect_equal(u$upd$tags, list(list(tag = "mine"), list(tag = "new")))
  expect_equal(u$res$n_tagged, 1L)

  o <- run("overwrite", tags[2, ])
  expect_equal(o$upd$tags, list(list(tag = "new")))

  # overwrite with no tags for the work removes them
  o <- run("overwrite", data.frame(openalex_id = "W9", tag = "x"))
  expect_equal(o$upd$tags, list())

  # update with nothing new leaves tags alone
  u <- run("update", tags[1, ])
  expect_null(u$upd$tags)
  expect_equal(u$res$n_tagged, 0L)
})

# POST /collections answers with a key made from the name
collections_route <- function(existing = "[]") {
  list(
    "GET /api/users/0/collections" = list(body = existing),
    "POST /api/users/0/collections" = function(req) {
      name <- jsonlite::fromJSON(req$body$data, simplifyVector = FALSE)[[1]]$name
      list(body = sprintf('{"success":{"0":"C_%s"},"unchanged":{},"failed":{}}', name))
    }
  )
}

collections_posted <- function(log) {
  lapply(
    Filter(function(r) r$method == "POST" && r$path == "/api/users/0/collections", log$requests),
    function(r) jsonlite::fromJSON(sent(r), simplifyVector = FALSE)[[1]]
  )
}

test_that("collection: nested path is created, existing levels reused", {
  log <- mock_zotero(collections_route(
    '[{"data":{"key":"P","name":"proj","parentCollection":false}},
      {"data":{"key":"OLD","name":"corpus","parentCollection":false}},
      {"data":{"key":"GONE","name":"corpus","parentCollection":"P","deleted":true}}]'
  ))
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  expect_equal(.zotero_collection(api, c("proj", "corpus")), "C_corpus")
  expect_equal(collections_posted(log), list(list(name = "corpus", parentCollection = "P")))
  expect_equal(.zotero_collection(api, "proj"), "P")
})

test_that("collection: new, skipped and updated works all join it", {
  for (mode in c("skip", "update")) {
    log <- mock_zotero(c(collections_route(), list(
      "GET /api/users/0/items" = function(req) {
        list(body = if (grepl("itemKey=N1", req$url)) {
          '[{"data":{"key":"N1","version":3,"collections":["SEL"]}}]'
        } else {
          existing_items("W1")
        })
      },
      "POST /connector/import" = function(req) {
        list(status = 201L, body = if (grepl("W2", req$body$data)) {
          '[{"key":"N1","extra":"OpenAlex: W2"}]'
        } else {
          '[{"key":"TMP","title":"t","extra":"OpenAlex: W1"}]'
        })
      },
      "POST /api/users/0/items" = list(body = '{"success":{"0":"X"},"unchanged":{},"failed":{}}'),
      "DELETE /api/users/0/items" = list(status = 204L)
    )))
    res <- suppressMessages(csljson_to_zotero(
      csl_files(1L, ids = c("W1", "W2")), existing = mode,
      collection = c("proj", "corpus"), api_key = "KEY"
    ))
    expect_true(res$ok, label = mode)
    expect_length(collections_posted(log), 2L)
    p <- posted(log)
    old <- Filter(function(o) o$key == "OLD1", p)[[1]]
    expect_equal(old$collections, list("C_corpus"), label = mode)
    new <- Filter(function(o) o$key == "N1", p)[[1]]
    expect_equal(new, list(key = "N1", version = 3L, collections = list("SEL", "C_corpus")))
  }
})

test_that("collection: works already in it are not written again", {
  api <- list(url = "u", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  log <- mock_zotero()
  res <- .zotero_add_to_collection(api, list(list(key = "K", version = 1L, collections = list("C"))), "C")
  expect_equal(res$n, 0L)
  expect_length(log$requests, 0L)
})

test_that("corpus_to_zotero: default collection is <project> > <corpus>", {
  log <- mock_zotero(collections_route())
  suppressMessages(corpus_to_zotero(
    project_dir = testthat::test_path("..", "fixtures"),
    corpus = testthat::test_path("..", "fixtures", "corpus"),
    api_key = "KEY"
  ))
  expect_equal(collections_posted(log), list(
    list(name = "fixtures", parentCollection = FALSE),
    list(name = "corpus", parentCollection = "C_fixtures")
  ))
})

test_that("import errors: unreachable connector and unexpected status", {
  mock_zotero(list("POST /connector/import" = function(req) stop("connection reset")))
  res <- suppressMessages(csljson_to_zotero(csl_files(1L)))
  expect_false(res$ok)
  expect_true(is.na(res$status_code))
  expect_match(res$message, "connection reset")

  mock_zotero(list("POST /connector/import" = list(status = 500L, body = "Internal error")))
  res <- suppressMessages(csljson_to_zotero(csl_files(1L)))
  expect_false(res$ok)
  expect_equal(res$status_code, 500L)
  expect_equal(res$message, "Internal error")
})

test_that("update: a failed import of the known works is reported", {
  mock_zotero(list(
    "GET /api/users/0/items" = list(body = existing_items("W1")),
    "POST /connector/import" = list(status = 500L, body = "busy")
  ))
  res <- suppressMessages(csljson_to_zotero(
    csl_files(1L, ids = "W1"), existing = "update", api_key = "KEY"
  ))
  expect_false(res$ok)
  expect_equal(res$n_updated, 0L)
  expect_equal(res$message, "busy")
})

test_that("update: copies that cannot be deleted are reported", {
  mock_zotero(list(
    "GET /api/users/0/items" = list(body = existing_items("W1")),
    "POST /connector/import" = list(
      status = 201L, body = '[{"key":"TMP","title":"t","extra":"OpenAlex: W1"}]'
    ),
    "POST /api/users/0/items" = list(body = '{"success":{"0":"OLD1"},"unchanged":{},"failed":{}}'),
    "DELETE /api/users/0/items" = list(status = 412L)
  ))
  res <- suppressMessages(csljson_to_zotero(
    csl_files(1L, ids = "W1"), existing = "update", api_key = "KEY"
  ))
  expect_false(res$ok)
  expect_equal(res$n_updated, 1L) # the update itself went through
  expect_equal(res$message, "Could not delete temporary copies: TMP")
})

test_that("overwrite empties text fields and creators the new item lacks", {
  old <- list(
    key = "OLD", version = 4L, title = "old", abstractNote = "old abstract",
    creators = list(list(lastName = "Doe")), tags = list(list(tag = "keep")),
    collections = list("C"), numPages = 3L
  )
  new <- list(key = "TMP", version = 0L, title = "new", url = "", tags = list())
  upd <- .zotero_update_object(new, old, blank = TRUE)
  expect_equal(upd$title, "new")
  expect_equal(upd$abstractNote, "")
  expect_equal(upd$creators, list())
  expect_null(upd$url) # empty new values are not written
  expect_null(upd$numPages) # only text fields are emptied
  expect_null(upd$tags)
  expect_null(upd$collections)
  expect_equal(upd[c("key", "version")], list(key = "OLD", version = 4L))

  # update keeps what the new item lacks
  upd <- .zotero_update_object(new, old, blank = FALSE)
  expect_named(upd, c("title", "key", "version"))
})

test_that(".zotero_post_items fails on a rejected write", {
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  mock_zotero(list("POST /api/users/0/items" = list(status = 403L, body = "Forbidden")))
  expect_error(
    .zotero_post_items(api, list(list(key = "K", version = 1L))),
    "Writing to Zotero failed: Forbidden"
  )
})

test_that("tags can be read from a parquet file", {
  f <- tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(openalex_id = "w1", tag = "a", type = 1L), f)
  expect_equal(.tag_index(f), list(W1 = list(list(tag = "a", type = 1L))))
})

test_that("new items without tags or collection need no second write", {
  api <- list(url = "u", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  log <- mock_zotero()
  res <- .zotero_finish_new(api, list(list(key = "N1", extra = "OpenAlex: W2")), list(W1 = list(list(tag = "a"))))
  expect_equal(res, list(n = 0L, n_tagged = 0L, message = ""))
  expect_length(log$requests, 0L)
})

test_that("collection: a refused creation is an error", {
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  mock_zotero(list(
    "GET /api/users/0/collections" = list(body = "[]"),
    "POST /api/users/0/collections" = list(
      body = '{"success":{},"unchanged":{},"failed":{"0":{"message":"bad name"}}}'
    )
  ))
  expect_error(.zotero_collection(api, "proj"), "Could not create Zotero collection 'proj'")
})

test_that("collection: a non-JSON error response gives the Zotero message", {
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID", key = "KEY")
  mock_zotero(list(
    "GET /api/users/0/collections" = list(body = "[]"),
    "POST /api/users/0/collections" = list(status = 403L, body = "Forbidden")
  ))
  expect_error(.zotero_collection(api, "proj"), "Could not create Zotero collection 'proj': Forbidden")
})

test_that("local API key: asked once, then cached for the session", {
  on.exit(.zotero_env$key <- NULL, add = TRUE)
  .zotero_env$key <- NULL
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID")
  log <- mock_zotero(list(
    "POST /api/local/authorize" = list(body = '{"key":"NEWKEY","remember":true}')
  ))
  expect_message(key <- .zotero_local_key(api), "Always Allow")
  expect_equal(key, "NEWKEY")
  auth <- log$requests[[1]]
  expect_equal(auth$req$headers$`Zotero-Server-ID`, "SID")
  expect_equal(sent(auth)$appName, "openalexConvert")

  expect_equal(.zotero_local_key(api), "NEWKEY")
  expect_length(log$requests, 1L) # no second dialog
})

test_that("local API key: refused or one-off access is an error", {
  on.exit(.zotero_env$key <- NULL, add = TRUE)
  .zotero_env$key <- NULL
  api <- list(url = "http://127.0.0.1:23119", prefix = "/api/users/0", server_id = "SID")
  mock_zotero(list("POST /api/local/authorize" = list(status = 403L, body = "{}")))
  expect_error(suppressMessages(.zotero_local_key(api)), "did not grant write access")
  # a plain-text (non-JSON) error body gives the same message
  mock_zotero(list("POST /api/local/authorize" = list(status = 403L, body = "Forbidden")))
  expect_error(suppressMessages(.zotero_local_key(api)), "did not grant write access")

  mock_zotero(list(
    "POST /api/local/authorize" = list(body = '{"key":"ONCE","remember":false}')
  ))
  expect_error(suppressMessages(.zotero_local_key(api)), "choose 'Always Allow'")
  expect_null(.zotero_env$key)
})

test_that("update without api_key asks Zotero for one", {
  on.exit(.zotero_env$key <- NULL, add = TRUE)
  .zotero_env$key <- NULL
  log <- mock_zotero(list(
    "POST /api/local/authorize" = list(body = '{"key":"ASKED","remember":true}'),
    "GET /api/users/0/items" = list(body = existing_items("W1")),
    "POST /connector/import" = list(
      status = 201L, body = '[{"key":"TMP","title":"t","extra":"OpenAlex: W1"}]'
    ),
    "POST /api/users/0/items" = list(body = '{"success":{"0":"OLD1"},"unchanged":{},"failed":{}}'),
    "DELETE /api/users/0/items" = list(status = 204L)
  ))
  res <- suppressMessages(csljson_to_zotero(
    csl_files(1L, ids = "W1"), existing = "update", api_key = ""
  ))
  expect_true(res$ok)
  post <- Filter(function(r) r$method == "POST" && r$path == "/api/users/0/items", log$requests)[[1]]
  expect_equal(post$req$headers$`Zotero-API-Key`, "ASKED")
})
