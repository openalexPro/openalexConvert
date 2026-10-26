#' Import CSL JSON files into Zotero
#'
#' @description
#' Import one or more CSL JSON files (e.g. the chunks written by
#' [corpus_to_csljson()]) into Zotero.
#'
#' - `method = "local"` sends each file to a running Zotero desktop app via its
#'   local connector endpoint (`/connector/import`, the endpoint the browser
#'   connector uses). Zotero's own CSL JSON importer does the mapping. Items
#'   go into the library or collection **currently selected in Zotero**; select
#'   a group library there to import into the group, and Zotero sync uploads
#'   them.
#' - `method = "web"` (headless upload via the Zotero Web API) is not
#'   implemented yet and raises an error.
#'
#' Zotero imports the CSL `note` into **Extra**; for files written by
#' [corpus_to_csljson()] its first line is the item's `OpenAlex: W...`.
#'
#' Importing the same files twice creates duplicate items.
#'
#' Progress is reported via the \pkg{progressr} package.
#'
#' @param files Character vector. Paths to CSL JSON files. If a single element
#'   points to an existing directory, all `*.json` files in that directory
#'   (non-recursive) are used.
#' @param method `"local"` (default) or `"web"`. See Description.
#' @param url Base URL of the local Zotero connector server. Default
#'   `"http://127.0.0.1:23119"`.
#' @param timeout Seconds to wait for Zotero to import one file. Default
#'   `3600`; a 10000-item chunk takes several minutes.
#'
#' @return
#' Invisibly, a data.frame with one row per file and columns:
#' \describe{
#'   \item{file}{Path to the CSL JSON file.}
#'   \item{status_code}{HTTP status code returned by Zotero (`201` on success).}
#'   \item{ok}{Logical; `TRUE` if the file was imported.}
#'   \item{n_items}{Number of items Zotero reports as imported.}
#'   \item{message}{Character; error text if the import failed.}
#' }
#'
#' @examples
#' \dontrun{
#' # In Zotero, select the target library or collection first.
#' res <- csljson_to_zotero("csljson")  # directory with chunk_1.json, ...
#' subset(res, !ok)
#' }
#'
#' @importFrom httr2 request req_url_path req_url_query req_body_file
#' @importFrom httr2 req_body_json req_error req_timeout req_perform
#' @importFrom httr2 resp_status resp_has_body resp_body_string
#' @importFrom progressr with_progress progressor
#' @md
#'
#' @export
csljson_to_zotero <- function(
  files,
  method = c("local", "web"),
  url = "http://127.0.0.1:23119",
  timeout = 3600
) {
  method <- match.arg(method)
  if (method == "web") {
    stop(
      "Upload via the Zotero Web API (method = \"web\") is not implemented yet.",
      call. = FALSE
    )
  }

  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.json$", full.names = TRUE)
  }
  stopifnot(length(files) > 0L)

  # Zotero must be running, and the selected target must accept new items
  target <- tryCatch(
    httr2::request(url) |>
      httr2::req_url_path("/connector/getSelectedCollection") |>
      httr2::req_body_json(list()) |>
      httr2::req_perform() |>
      httr2::resp_body_string() |>
      jsonlite::fromJSON(simplifyVector = FALSE),
    error = function(e) {
      stop(
        "Cannot reach Zotero at ", url, ". Is the Zotero desktop app running?",
        call. = FALSE
      )
    }
  )
  if (!isTRUE(target$editable)) {
    stop(
      "The library/collection selected in Zotero ('", target$name,
      "') is read-only. Select an editable one and try again.",
      call. = FALSE
    )
  }
  message(
    "Importing ", length(files), " file(s) into Zotero: ",
    target$libraryName,
    if (!is.null(target$id)) paste0(" / ", target$name)
  )

  session <- paste0("openalexConvert-", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  results <- vector("list", length(files))

  progressr::with_progress({
    p <- progressr::progressor(along = files)

    for (i in seq_along(files)) {
      f <- files[[i]]
      p(message = sprintf("Importing %d/%d: %s", i, length(files), basename(f)))

      res <- list(
        file = f,
        status_code = NA_integer_,
        ok = FALSE,
        n_items = 0L,
        message = ""
      )

      if (!file.exists(f)) {
        res$message <- "File does not exist"
        results[[i]] <- res
        next
      }

      req <- httr2::request(url) |>
        httr2::req_url_path("/connector/import") |>
        httr2::req_url_query(session = paste0(session, "-", i)) |>
        # text/plain: with application/json Zotero parses the body itself and
        # the import translators never see the raw text
        httr2::req_body_file(f, type = "text/plain") |>
        httr2::req_timeout(timeout) |>
        httr2::req_error(is_error = function(resp) FALSE)

      resp <- try(httr2::req_perform(req), silent = TRUE)

      if (inherits(resp, "try-error")) {
        res$message <- as.character(resp)
      } else {
        res$status_code <- httr2::resp_status(resp)
        body <- if (httr2::resp_has_body(resp)) {
          httr2::resp_body_string(resp)
        } else {
          ""
        }
        if (res$status_code == 201L) {
          res$ok <- TRUE
          res$n_items <- length(jsonlite::fromJSON(body, simplifyVector = FALSE))
        } else if (res$status_code == 400L) {
          res$message <- "Zotero found no importer for this file (not CSL JSON?)"
        } else {
          res$message <- substr(body, 1L, 500L)
        }
      }

      results[[i]] <- res
    }
  })

  out <- do.call(rbind, lapply(results, as.data.frame))
  rownames(out) <- NULL
  invisible(out)
}
