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
#' @return Invisibly returns the normalized path to the created file.
#'
#' @importFrom jsonlite read_json write_json
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

  # Merge the chunked CSL JSON into a single array before conversion so that
  # `output` is a single file (e.g. `corpus.bib`) rather than a directory of
  # per-chunk files (which is what passing the directory to
  # `csljson_convert_pandoc()` would produce).
  chunk_files <- sort(list.files(
    csl_tmp,
    pattern = "^chunk_\\d+\\.json$",
    full.names = TRUE
  ))
  if (!length(chunk_files)) {
    stop("No CSL JSON chunks were produced from `corpus`.")
  }
  items <- unlist(
    lapply(chunk_files, jsonlite::read_json),
    recursive = FALSE
  )
  combined <- tempfile(fileext = ".json")
  on.exit(try(unlink(combined, force = TRUE), silent = TRUE), add = TRUE)
  jsonlite::write_json(items, combined, auto_unbox = TRUE, pretty = FALSE)

  out_path <- csljson_convert_pandoc(combined, output, to = to)
  invisible(out_path)
}
