#' One-shot export via CSL JSON + Pandoc
#'
#' Convenience wrapper that maps a corpus to CSL JSON, then converts it to the
#' desired output format via Pandoc.
#'
#' @param corpus Arrow Dataset/Table or data.frame/tibble of works.
#' @param output Path to the final file (e.g., `corpus.bib`).
#' @param to Target format passed to Pandoc (e.g., `"bibtex"`, `"biblatex"`).
#' @param csl_tmp Optional path for a temporary CSL JSON directory. If `NULL`, a
#'   temporary directory is used and removed afterwards.
#' @param ... Additional arguments passed to `corpus_to_csljson()`
#'   (e.g., `chunk_size`).
#'
#' @return Invisibly returns `normalizePath(output)`.
#'
#' @export
corpus_export_via_pandoc <- function(
  corpus,
  output,
  to = c("bibtex", "biblatex"),
  csl_tmp = NULL,
  ...
) {
  to <- match.arg(to)
  remove_tmp <- FALSE
  if (is.null(csl_tmp)) {
    # `corpus_to_csljson()` creates the directory itself and errors if it
    # already exists, so only reserve the path here.
    csl_tmp <- tempfile(pattern = "csljson_")
    remove_tmp <- TRUE
  }
  corpus_to_csljson(corpus = corpus, output = csl_tmp, ...)
  on.exit(
    if (remove_tmp) {
      try(unlink(csl_tmp, recursive = TRUE, force = TRUE), silent = TRUE)
    },
    add = TRUE
  )
  csljson_convert_pandoc(csl_tmp, output, to = to)
  invisible(normalizePath(output))
}
