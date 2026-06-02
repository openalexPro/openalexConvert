test_that("corpus_export_via_pandoc one-shot wrapper produces a .bib", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")

  out_dir <- tempfile("export_")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)
  out_bib <- file.path(out_dir, "corpus.bib")

  res <- corpus_export_via_pandoc(
    corpus = input_dir,
    output = out_bib,
    to = "bibtex",
    chunk_size = 100
  )
  # Must be a single file, not a directory of per-chunk .bib files.
  expect_false(dir.exists(res))
  expect_true(file.exists(res))
  expect_true(file.info(res)$size > 0)
})

test_that("corpus_export_via_pandoc honours an explicit csl_tmp dir", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")

  out_dir <- tempfile("export_")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)
  csl_tmp <- file.path(out_dir, "csl")

  res <- corpus_export_via_pandoc(
    corpus = input_dir,
    output = file.path(out_dir, "out"),
    to = "biblatex",
    csl_tmp = csl_tmp,
    chunk_size = 100
  )
  # Output extension is added when missing; result is a single file.
  expect_false(dir.exists(res))
  expect_true(file.exists(res))
  expect_identical(tools::file_ext(res), "bib")
  expect_true(file.info(res)$size > 0)
  # When csl_tmp is supplied it is not removed afterwards.
  expect_true(dir.exists(csl_tmp))
  expect_true(length(list.files(csl_tmp, pattern = "chunk_\\d+\\.json$")) >= 1)
})

test_that("csljson_convert_pandoc renders html for a directory of chunks", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")

  csl_dir <- tempfile("csljson_")
  dir.create(csl_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(csl_dir, recursive = TRUE, force = TRUE), add = TRUE)
  corpus_to_csljson(
    corpus = input_dir,
    output = csl_dir,
    chunk_size = 100,
    overwrite = TRUE,
    verbose = FALSE
  )

  out_html_dir <- tempfile("html_")
  on.exit(unlink(out_html_dir, recursive = TRUE, force = TRUE), add = TRUE)
  html_path <- csljson_convert_pandoc(
    csl_dir,
    out_html_dir,
    to = "html",
    overwrite = TRUE,
    verbose = FALSE
  )
  expect_true(file.exists(html_path))
  expect_identical(basename(html_path), "references.html")
  expect_true(file.info(html_path)$size > 0)
})

test_that("csljson_convert_pandoc renders a single file to markdown", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")

  csl_dir <- tempfile("csljson_")
  dir.create(csl_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(csl_dir, recursive = TRUE, force = TRUE), add = TRUE)
  corpus_to_csljson(
    corpus = input_dir,
    output = csl_dir,
    chunk_size = 100,
    overwrite = TRUE,
    verbose = FALSE
  )
  chunk1 <- file.path(csl_dir, "chunk_1.json")

  out_base <- tempfile("refs_")
  on.exit(unlink(paste0(out_base, ".md"), force = TRUE), add = TRUE)
  # No extension supplied -> the function appends ".md".
  md_path <- csljson_convert_pandoc(
    chunk1,
    out_base,
    to = "markdown",
    overwrite = TRUE,
    verbose = FALSE
  )
  expect_true(file.exists(md_path))
  expect_identical(tools::file_ext(md_path), "md")
  md_txt <- readLines(md_path, warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("^:{3,}", md_txt)))
})

test_that("csljson_convert_pandoc errors on missing input or existing out", {
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")

  expect_error(
    csljson_convert_pandoc("does-not-exist.json", tempfile(), to = "bibtex"),
    "does not exist"
  )

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")
  csl_dir <- tempfile("csljson_")
  dir.create(csl_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(csl_dir, recursive = TRUE, force = TRUE), add = TRUE)
  corpus_to_csljson(
    corpus = input_dir,
    output = csl_dir,
    chunk_size = 100,
    overwrite = TRUE,
    verbose = FALSE
  )

  out_dir <- tempfile("bib_")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)
  csljson_convert_pandoc(csl_dir, out_dir, to = "bibtex", verbose = FALSE)
  # Second run without overwrite must refuse to clobber.
  expect_error(
    csljson_convert_pandoc(csl_dir, out_dir, to = "bibtex", verbose = FALSE),
    "exists"
  )
})

test_that("corpus_to_csljson rejects missing args and existing output", {
  expect_error(corpus_to_csljson(corpus = NULL), "`corpus` must be provided")

  input_dir <- testthat::test_path("..", "fixtures", "corpus")
  skip_if_not(dir.exists(input_dir), "fixtures corpus not available")
  out_dir <- tempfile("csljson_")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)
  expect_error(
    corpus_to_csljson(corpus = input_dir, output = out_dir, overwrite = FALSE),
    "exists"
  )
})
