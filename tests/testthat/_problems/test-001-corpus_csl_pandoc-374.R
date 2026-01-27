# Extracted from test-001-corpus_csl_pandoc.R:374

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
chunk1 <- file.path(csl_dir, "chunk_1.json")
expect_true(file.exists(chunk1))
tmp_dir <- tempfile("bib_")
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
out_bib <- file.path(tmp_dir, "chunk_1_single.bib")
path_out <- csljson_convert_pandoc(
    chunk1,
    out_bib,
    to = "bibtex",
    overwrite = TRUE,
    verbose = FALSE
  )
expect_true(file.exists(path_out))
expect_true(file.info(path_out)$size > 0)
fx_btx_dir <- testthat::test_path("..", "fixtures", "corpus_bibtex")
skip_if_not(dir.exists(fx_btx_dir), "fixtures corpus_bibtex not available")
fx_bib <- file.path(fx_btx_dir, "chunk_1.bib")
expect_true(file.exists(fx_bib))
expect_equal(
    readLines(path_out, warn = FALSE, encoding = "UTF-8"),
    readLines(fx_bib, warn = FALSE, encoding = "UTF-8")
  )
