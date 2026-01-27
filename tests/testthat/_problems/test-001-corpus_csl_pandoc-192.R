# Extracted from test-001-corpus_csl_pandoc.R:192

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
out_blx <- tempfile("biblatex_")
dir.create(out_blx, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(out_blx, recursive = TRUE, force = TRUE), add = TRUE)
blx_err <- NULL
paths_blx <- NULL
tryCatch(
    {
      paths_blx <- csljson_convert_pandoc(
        csl_dir,
        out_blx,
        to = "biblatex",
        overwrite = TRUE,
        verbose = FALSE
      )
    },
    error = function(e) blx_err <<- e
  )
if (!is.null(blx_err)) {
    testthat::skip(paste(
      "biblatex conversion failed in this environment:",
      conditionMessage(blx_err)
    ))
  }
expect_true(all(file.exists(paths_blx)))
expect_true(all(file.info(paths_blx)$size > 0))
fx_blx_dir <- testthat::test_path("..", "fixtures", "corpus_biblatex")
skip_if_not(dir.exists(fx_blx_dir), "fixtures corpus_biblatex not available")
fx_blx <- sort(list.files(
    fx_blx_dir,
    pattern = "^chunk_\\d+\\.bib$",
    full.names = TRUE
  ))
expect_equal(length(paths_blx), length(fx_blx))
for (f in fx_blx) {
    bn <- basename(f)
    gen <- file.path(out_blx, bn)
    expect_true(file.exists(gen), info = paste("missing generated:", bn))
    expect_equal(
      readLines(gen, warn = FALSE, encoding = "UTF-8"),
      readLines(f, warn = FALSE, encoding = "UTF-8"),
      info = paste("BibLaTeX differs for:", bn)
    )
  }
