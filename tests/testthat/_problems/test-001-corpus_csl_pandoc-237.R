# Extracted from test-001-corpus_csl_pandoc.R:237

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "openalexConvert", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
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
out_md_dir <- tempfile("md_")
dir.create(out_md_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(out_md_dir, recursive = TRUE, force = TRUE), add = TRUE)
md_path <- csljson_convert_pandoc(
    csl_dir,
    out_md_dir,
    to = "markdown",
    overwrite = TRUE,
    verbose = FALSE
  )
expect_true(file.exists(md_path))
md_txt <- readLines(md_path, warn = FALSE, encoding = "UTF-8")
expect_true(length(md_txt) > 0)
expect_true(any(grepl("^# +References$", md_txt)))
expect_false(any(grepl("^:{3,}", md_txt)))
fx_docs_dir <- testthat::test_path("..", "fixtures", "corpus_docs")
skip_if_not(dir.exists(fx_docs_dir), "fixtures corpus_docs not available")
fx_md <- file.path(fx_docs_dir, "references.md")
expect_true(file.exists(fx_md))
expect_equal(
    readLines(md_path, warn = FALSE, encoding = "UTF-8"),
    readLines(fx_md, warn = FALSE, encoding = "UTF-8")
  )
