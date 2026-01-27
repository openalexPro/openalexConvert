# Extracted from test-001-corpus_csl_pandoc.R:276

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
out_tex_dir <- tempfile("tex_")
dir.create(out_tex_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(out_tex_dir, recursive = TRUE, force = TRUE), add = TRUE)
tex_path <- csljson_convert_pandoc(
    csl_dir,
    out_tex_dir,
    to = "latex",
    overwrite = TRUE,
    verbose = FALSE
  )
fx_docs_dir <- testthat::test_path("..", "fixtures", "corpus_docs")
skip_if_not(dir.exists(fx_docs_dir), "fixtures corpus_docs not available")
fx_tex <- file.path(fx_docs_dir, "references.tex")
expect_true(file.exists(tex_path))
expect_true(file.exists(fx_tex))
expect_equal(
    readLines(tex_path, warn = FALSE, encoding = "UTF-8"),
    readLines(fx_tex, warn = FALSE, encoding = "UTF-8")
  )
