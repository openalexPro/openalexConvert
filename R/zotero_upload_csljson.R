#' Upload CSL JSON batch files to a Zotero group library
#'
#' @description
#' Upload one or more CSL-JSON files to a Zotero **group** library using the
#' Zotero Web API. Each file is assumed to contain an array of item objects
#' suitable for POSTing to `/groups/{group_id}/items`.
#'
#' This is designed for bulk import workflows where you pre-generate CSL-JSON
#' batches (e.g. 40 items per file) and then upload them in a controlled way.
#'
#' @param files Character vector. Paths to CSL-JSON files. If a single element
#'   points to an existing directory, all `*.json` files in that directory
#'   (non-recursive) are used. Each individual json file must contain less then 50 works.
#' @param group_id Character or numeric. Zotero **group** ID.
#' @param api_key Character. Zotero API key with write access to the group.
#'   Defaults to `Sys.getenv("ZOTERO_API_KEY")`.
#' @param pause Numeric scalar. Number of seconds to wait between requests
#'   (to avoid rate limiting). Default is `0.5`.
#' @param verbose Logical. If `TRUE`, print progress messages. Default `TRUE`.
#'
#' @return
#' A data.frame with one row per file and columns:
#' \describe{
#'   \item{file}{Path to the CSL-JSON file.}
#'   \item{status_code}{HTTP status code returned by the Zotero API.}
#'   \item{ok}{Logical; `TRUE` if `status_code` is in 200–299.}
#'   \item{message}{Character; short message or error text.}
#' }
#' Invisibly returns this data.frame.
#'
#' @examples
#' \dontrun{
#' res <- zotero_upload_csljson(
#'   files   = "csljson_batches",  # directory with *.json, ...
#'   group_id = "123456",
#'   api_key  = Sys.getenv("ZOTERO_API_KEY")
#' )
#' }
#'
#' @importFrom httr2 request req_headers req_body_raw req_perform
#' @importFrom httr2 resp_status resp_body_string
zotero_upload_csljson <- function(
  files,
  group_id,
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  pause = 0.5,
  verbose = TRUE
) {
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.json$", full.names = TRUE)
  }

  stopifnot(length(files) > 0L)

  if (!nzchar(api_key)) {
    stop(
      "Zotero API key is empty. Set 'api_key' or ZOTERO_API_KEY env var.",
      call. = FALSE
    )
  }

  endpoint <- sprintf("https://api.zotero.org/groups/%s/items", group_id)

  results <- vector("list", length(files))

  for (i in seq_along(files)) {
    f <- files[[i]]

    if (verbose) {
      message(sprintf("Uploading [%d/%d]: %s", i, length(files), f))
    }

    if (!file.exists(f)) {
      msg <- "File does not exist"
      if (verbose) {
        message("  -> ERROR: ", msg)
      }
      results[[i]] <- list(
        file = f,
        status_code = NA_integer_,
        ok = FALSE,
        message = msg
      )
      next
    }

    body <- paste(readLines(f, warn = FALSE), collapse = "\n")

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Zotero-API-Key" = api_key,
        "Content-Type" = "application/json",
        "Zotero-API-Version" = "3"
      ) |>
      httr2::req_body_raw(body = charToRaw(body), type = "application/json")

    status_code <- NA_integer_
    ok <- FALSE
    msg <- ""

    # basic error handling
    resp <- try(httr2::req_perform(req), silent = TRUE)

    if (inherits(resp, "try-error")) {
      msg <- as.character(resp)
      if (verbose) message("  -> ERROR: ", msg)
    } else {
      status_code <- httr2::resp_status(resp)
      ok <- status_code >= 200L && status_code < 300L

      if (!ok) {
        body_txt <- httr2::resp_body_string(resp)
        # keep body message short-ish
        msg <- substr(body_txt, 1L, 500L)
        if (verbose) {
          message(sprintf("  -> HTTP %d", status_code))
          message("  -> Response (truncated): ", msg)
        }
      } else if (verbose) {
        message(sprintf("  -> OK (HTTP %d)", status_code))
      }
    }

    results[[i]] <- list(
      file = f,
      status_code = status_code,
      ok = ok,
      message = msg
    )

    if (i < length(files) && pause > 0) {
      Sys.sleep(pause)
    }
  }

  out <- do.call(
    rbind,
    lapply(results, function(x) {
      data.frame(
        file = x$file,
        status_code = x$status_code,
        ok = x$ok,
        message = x$message,
        stringsAsFactors = FALSE
      )
    })
  )

  rownames(out) <- NULL
  invisible(out)
}
