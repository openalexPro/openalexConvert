# Extracted from test-001-corpus_csl_pandoc.R:128

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
out_btx <- tempfile("bibtex_")
dir.create(out_btx, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(out_btx, recursive = TRUE, force = TRUE), add = TRUE)
paths_btx <- csljson_convert_pandoc(
    csl_dir,
    out_btx,
    to = "bibtex",
    overwrite = TRUE,
    verbose = FALSE
  )
expect_true(all(file.exists(paths_btx)))
expect_true(all(file.info(paths_btx)$size > 0))
fx_btx_dir <- testthat::test_path("..", "fixtures", "corpus_bibtex")
skip_if_not(dir.exists(fx_btx_dir), "fixtures corpus_bibtex not available")
fx_btx <- sort(list.files(
    fx_btx_dir,
    pattern = "^chunk_\\d+\\.bib$",
    full.names = TRUE
  ))
expect_equal(length(paths_btx), length(fx_btx))
for (f in fx_btx) {
    bn <- basename(f)
    gen <- file.path(out_btx, bn)
    expect_true(file.exists(gen), info = paste("missing generated:", bn))
    expect_equal(
      readLines(gen, warn = FALSE, encoding = "UTF-8"),
      readLines(f, warn = FALSE, encoding = "UTF-8"),
      info = paste("BibTeX differs for:", bn)
    )
  }
