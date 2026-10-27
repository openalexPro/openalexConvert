#' One-shot export of a corpus to Zotero
#'
#' Convenience wrapper: maps a corpus to CSL JSON with [corpus_to_csljson()]
#' (in a temporary directory, removed afterwards) and imports it into the
#' library or collection selected in Zotero with [csljson_to_zotero()]. See
#' there for re-exports (`existing`) and the import speed.
#'
#' @param project_dir Optional path to the project directory, used for the
#'   default of `corpus`.
#' @param corpus Path to parquet dataset, Arrow Dataset/Table or
#'   data.frame/tibble of works. Default `file.path(project_dir, "parquet")`.
#' @param existing `"skip"` (default), `"update"` or `"overwrite"`: what to do
#'   with works already in the Zotero library. See [csljson_to_zotero()].
#' @param tags Tags to write, by OpenAlex ID (see "Tags" in
#'   [csljson_to_zotero()]): a data.frame, a parquet path, or `NULL` for none.
#'   Default: `<project_dir>/zotero_tags.parquet` (written by [zotero_tags()])
#'   if it exists, else `NULL`.
#' @param chunk_size Works per file sent to Zotero. Default `1000`, which
#'   gives progress per 1000 works and stays well within `timeout`.
#' @param ... Further arguments to [csljson_to_zotero()] (`method`, `url`,
#'   `api_key`, `timeout`).
#'
#' @return Invisibly, the data.frame returned by [csljson_to_zotero()], one
#'   row per chunk.
#'
#' @examples
#' \dontrun{
#' # In Zotero, select the target library or collection first.
#' res <- corpus_to_zotero("my_project")
#' subset(res, !ok)
#' }
#'
#' @md
#'
#' @export
corpus_to_zotero <- function(
  project_dir,
  corpus = file.path(project_dir, "parquet"),
  existing = c("skip", "update", "overwrite"),
  tags,
  chunk_size = 1000,
  ...
) {
  if (missing(tags)) {
    tags <- if (!missing(project_dir)) file.path(project_dir, "zotero_tags.parquet")
    if (!is.null(tags) && !file.exists(tags)) tags <- NULL
  }
  csl_tmp <- tempfile(pattern = "csljson_")
  on.exit(try(unlink(csl_tmp, recursive = TRUE, force = TRUE), silent = TRUE), add = TRUE)
  corpus_to_csljson(
    corpus = corpus,
    output = csl_tmp,
    chunk_size = chunk_size,
    verbose = FALSE
  )
  csljson_to_zotero(csl_tmp, existing = existing, tags = tags, ...)
}
