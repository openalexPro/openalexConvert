#' Read Zotero tags by OpenAlex ID
#'
#' @description
#' Reads the tags of all items in the Zotero library **currently selected in
#' Zotero** whose Extra holds an OpenAlex ID (any of the forms listed in
#' [csljson_to_zotero()]) and writes them to a parquet file next to the
#' corpus. Tag works in Zotero, then join the table with the corpus on
#' `openalex_id`.
#'
#' The whole library is read, not only the selected collection. Rows of other
#' libraries already in `output` are kept; rows of this library are replaced,
#' so the file always holds the library's current tags. Items without an
#' OpenAlex ID in Extra are not included.
#'
#' Needs the running Zotero desktop app (Zotero 10 or later, for the local
#' API); reading needs no API key. It runs the same search as
#' [csljson_to_zotero()] (see its "Speed" section): a few seconds for a
#' library of 5000 works.
#'
#' @param project_dir Path to the project directory. Used for the default of
#'   `output`.
#' @param output Path of the parquet file. Default
#'   `file.path(project_dir, "zotero_tags.parquet")`.
#' @param url Base URL of the local Zotero server. Default
#'   `"http://127.0.0.1:23119"`.
#'
#' @return
#' Invisibly, a data.frame with one row per item and tag (the rows of this
#' library), as written to `output`:
#' \describe{
#'   \item{openalex_id}{OpenAlex work ID, e.g. `"W2112574986"`.}
#'   \item{tag}{The tag.}
#'   \item{type}{`0` for a tag added by hand, `1` for one added automatically
#'     (e.g. by an import translator).}
#'   \item{zotero_library}{Group ID, or `0` for the personal library.}
#'   \item{zotero_key}{Zotero item key.}
#' }
#' A work in the library twice gives rows for each Zotero item.
#'
#' @examples
#' \dontrun{
#' # In Zotero, select the library first.
#' tags <- zotero_tags("my_project")
#' # works tagged "include" in Zotero
#' unique(subset(tags, tag == "include")$openalex_id)
#' }
#'
#' @importFrom arrow write_parquet read_parquet
#' @md
#'
#' @export
zotero_tags <- function(
  project_dir,
  output = file.path(project_dir, "zotero_tags.parquet"),
  url = "http://127.0.0.1:23119"
) {
  target <- .zotero_selected(url)
  api <- .zotero_local_api(url, target$libraryName)
  library_id <- as.integer(sub(".*/", "", api$prefix))
  index <- .zotero_openalex_index(api)

  rows <- lapply(names(index), function(id) {
    lapply(index[[id]], function(it) {
      lapply(it$tags, function(t) {
        data.frame(
          openalex_id = id,
          tag = t$tag,
          type = as.integer(t$type %||% 0L),
          zotero_library = library_id,
          zotero_key = it$key
        )
      })
    })
  })
  tags <- do.call(rbind, c(
    list(data.frame(
      openalex_id = character(), tag = character(), type = integer(),
      zotero_library = integer(), zotero_key = character()
    )),
    unlist(unlist(rows, recursive = FALSE), recursive = FALSE)
  ))

  out <- tags
  if (file.exists(output)) {
    old <- as.data.frame(arrow::read_parquet(output))
    out <- rbind(old[old$zotero_library != library_id, names(tags)], tags)
  }
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(out, output)
  message(
    nrow(tags), " tag(s) on ", length(unique(tags$openalex_id)), " work(s) from ",
    target$libraryName, " written to ", output
  )
  invisible(tags)
}
