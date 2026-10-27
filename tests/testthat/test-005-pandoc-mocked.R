# csljson_convert_pandoc() without pandoc: rmarkdown::pandoc_convert() is
# mocked, so these tests check what this package decides (paths, extensions,
# overwrite, options, post-processing) and run wherever pandoc is missing.

# Fake pandoc: logs every call and writes a markdown-like file with the
# fenced div pandoc leaves around the references.
mock_pandoc <- function(available = TRUE, env = parent.frame()) {
  log <- new.env()
  log$calls <- list()
  testthat::local_mocked_bindings(
    pandoc_available = function(...) available,
    pandoc_convert = function(input, to = NULL, from = NULL, output = NULL,
                              citeproc = FALSE, options = NULL, ...) {
      log$calls[[length(log$calls) + 1L]] <- list(
        input = input, to = to, from = from, output = output,
        options = options, json = if (identical(from, "csljson")) {
          jsonlite::read_json(input)
        }
      )
      writeLines(c("# References", "", "::: {#refs .references}", "Ref 1", ":::"), output)
      invisible(output)
    },
    .package = "rmarkdown",
    .env = env
  )
  log
}

# Directory with chunk_<i>.json files; `abstract` sets the first item's.
csl_dir <- function(n = 2L, abstract = "short") {
  d <- tempfile("csl_")
  dir.create(d)
  for (i in seq_len(n)) {
    jsonlite::write_json(
      list(list(type = "article-journal", id = paste0("W", i), title = "t", abstract = abstract)),
      file.path(d, sprintf("chunk_%d.json", i)),
      auto_unbox = TRUE
    )
  }
  d
}

test_that("csljson_convert_pandoc errors when pandoc is not available", {
  mock_pandoc(available = FALSE)
  expect_error(
    csljson_convert_pandoc(csl_dir(), tempfile(), to = "bibtex"),
    "Pandoc is not available"
  )
})

test_that(".normalize_json_for_pandoc drops over-long abstracts only", {
  f <- tempfile(fileext = ".json")
  long <- strrep("a", 11)
  jsonlite::write_json(
    list(list(id = "W1", abstract = long), list(id = "W2", abstract = "ok")),
    f, auto_unbox = TRUE
  )
  res <- .normalize_json_for_pandoc(f, cap = 10)
  expect_true(res$sanitized)
  expect_false(identical(res$path, normalizePath(f)))
  j <- jsonlite::read_json(res$path)
  expect_null(j[[1]]$abstract)
  expect_equal(j[[2]]$abstract, "ok")

  kept <- .normalize_json_for_pandoc(f, drop_long_abstracts = FALSE, cap = 10)
  expect_false(kept$sanitized)
  expect_equal(jsonlite::read_json(kept$path)[[1]]$abstract, long)

  # a single CSL object instead of an array
  jsonlite::write_json(list(id = "W1", abstract = long), f, auto_unbox = TRUE)
  one <- .normalize_json_for_pandoc(f, cap = 10)
  expect_true(one$sanitized)
  expect_equal(jsonlite::read_json(one$path), list(id = "W1"))
  short <- .normalize_json_for_pandoc(f, cap = 100)
  expect_false(short$sanitized)

  # unreadable JSON: the original file is passed on untouched
  writeLines("not json", f)
  bad <- .normalize_json_for_pandoc(f)
  expect_identical(bad$path, normalizePath(f))
  expect_false(bad$sanitized)
})

test_that(".build_pandoc_options maps html, pdf and CSL options", {
  base <- c("--citeproc", "--bibliography=a.json", "--bibliography=b.json")
  expect_equal(.build_pandoc_options("docx", c("a.json", "b.json")), base)
  expect_equal(
    .build_pandoc_options("html", c("a.json", "b.json"), references_csl = "apa.csl"),
    c(base, "--standalone", "--csl=apa.csl")
  )
  pdf <- .build_pandoc_options(
    "pdf", "a.json",
    pdf_engine = "lualatex", pdf_mainfont = "Serif", pdf_sansfont = "",
    pdf_monofont = "Mono", pdf_cjk_mainfont = "Noto CJK", pdf_cjk_options = "Scale=0.9"
  )
  expect_equal(pdf, c(
    "--citeproc", "--bibliography=a.json", "--pdf-engine=lualatex",
    "-V", "mainfont=Serif", "-V", "monofont=Mono",
    "-V", "CJKmainfont=Noto CJK", "-V", "CJKoptions=Scale=0.9"
  ))
  expect_equal(
    .build_pandoc_options("pdf", "a.json", pdf_engine = NULL),
    c("--citeproc", "--bibliography=a.json")
  )
})

test_that(".ensure_dir creates directories and rejects files", {
  d <- file.path(tempfile("ens_"), "a", "b")
  expect_identical(.ensure_dir(d), normalizePath(d))
  expect_true(dir.exists(d))

  f <- tempfile()
  writeLines("x", f)
  expect_error(.ensure_dir(f), "must be a directory")
  expect_error(.ensure_dir(file.path(f, "sub")), "Could not create output directory")
})

test_that("directory -> bib: one .bib per chunk, overwrite and [sanitized]", {
  log <- mock_pandoc()
  input <- csl_dir(2L, abstract = strrep("a", 10001))
  out <- tempfile("bib_")
  msgs <- capture_messages(res <- csljson_convert_pandoc(input, out, to = "biblatex"))
  expect_equal(trimws(msgs), paste0(
    "Converting with pandoc: chunk_", 1:2, ".json -> chunk_", 1:2,
    ".bib (biblatex) [sanitized]"
  ))
  expect_equal(basename(res), c("chunk_1.bib", "chunk_2.bib"))
  expect_length(log$calls, 2L)
  expect_equal(log$calls[[1]]$to, "biblatex")
  expect_equal(log$calls[[1]]$from, "csljson")
  expect_null(log$calls[[1]]$json[[1]]$abstract) # dropped before pandoc

  expect_error(
    csljson_convert_pandoc(input, out, to = "biblatex", verbose = FALSE),
    "Set overwrite = TRUE"
  )
  writeLines("stale", res[1])
  csljson_convert_pandoc(input, out, to = "biblatex", overwrite = TRUE, verbose = FALSE)
  expect_false(identical(readLines(res[1]), "stale"))
})

test_that("directory input without chunk files is an error", {
  mock_pandoc()
  empty <- tempfile("csl_")
  dir.create(empty)
  expect_error(csljson_convert_pandoc(empty, tempfile(), to = "bibtex"), "No chunk_\\*\\.json")
  expect_error(csljson_convert_pandoc(empty, tempfile(), to = "html"), "No chunk_\\*\\.json")
})

test_that("directory -> formatted: references.<ext> from all chunks", {
  log <- mock_pandoc()
  input <- csl_dir(2L)
  out <- tempfile("md_")
  expect_message(
    res <- csljson_convert_pandoc(input, out, to = "markdown", references_csl = "apa.csl"),
    "Rendering formatted references: references.md (markdown)",
    fixed = TRUE
  )
  expect_identical(res, normalizePath(file.path(out, "references.md")))
  call <- log$calls[[1]]
  expect_equal(call$from, "markdown")
  expect_equal(sum(startsWith(call$options, "--bibliography=")), 2L)
  expect_true("--csl=apa.csl" %in% call$options)
  # the stub document cites everything
  expect_true(any(grepl('nocite: "@*"', readLines(call$input), fixed = TRUE)))
  # pandoc's fenced div is removed from markdown output
  expect_equal(readLines(res), c("# References", "", "Ref 1"))

  expect_error(
    csljson_convert_pandoc(input, out, to = "markdown", verbose = FALSE),
    "Set overwrite = TRUE"
  )
  writeLines("stale", res)
  csljson_convert_pandoc(input, out, to = "markdown", overwrite = TRUE, verbose = FALSE)
  expect_equal(readLines(res), c("# References", "", "Ref 1"))
  pdf <-csljson_convert_pandoc(
    input, out, to = "pdf", overwrite = TRUE, verbose = FALSE, pdf_mainfont = "Serif"
  )
  expect_identical(basename(pdf), "references.pdf")
  expect_true(all(c("--pdf-engine=xelatex", "mainfont=Serif") %in% log$calls[[3]]$options))
  # only markdown is post-processed
  expect_true(any(grepl("^:::", readLines(pdf))))
})

test_that("single file -> bib: extension, nested dir and overwrite", {
  log <- mock_pandoc()
  input <- file.path(csl_dir(1L, abstract = strrep("a", 10001)), "chunk_1.json")
  out <- file.path(tempfile("bib_"), "nested", "refs")
  expect_message(
    res <- csljson_convert_pandoc(input, out, to = "bibtex"),
    "chunk_1.json -> refs.bib (bibtex)",
    fixed = TRUE
  )
  expect_identical(res, normalizePath(paste0(out, ".bib")))
  expect_true(file.exists(res))
  # single files keep long abstracts
  expect_equal(nchar(log$calls[[1]]$json[[1]]$abstract), 10001L)

  expect_error(
    csljson_convert_pandoc(input, res, to = "bibtex", verbose = FALSE),
    "Output file exists"
  )
  csljson_convert_pandoc(input, res, to = "bibtex", overwrite = TRUE, verbose = FALSE)
  expect_length(log$calls, 2L)
})

test_that("single file -> formatted: extension, nested dir and overwrite", {
  log <- mock_pandoc()
  input <- file.path(csl_dir(1L), "chunk_1.json")
  out <- file.path(tempfile("doc_"), "nested", "refs")
  expect_message(
    res <- csljson_convert_pandoc(input, out, to = "latex"),
    "Rendering formatted references: refs.tex (latex)",
    fixed = TRUE
  )
  expect_identical(res, normalizePath(paste0(out, ".tex")))
  expect_true(paste0("--bibliography=", normalizePath(input)) %in% log$calls[[1]]$options)

  expect_error(
    csljson_convert_pandoc(input, res, to = "latex", verbose = FALSE),
    "Output file exists"
  )
  html <- csljson_convert_pandoc(
    input, res, to = "html", overwrite = TRUE, verbose = FALSE
  )
  # an explicit extension is kept even if it does not match `to`
  expect_identical(html, res)
  expect_true("--standalone" %in% log$calls[[2]]$options)
})
