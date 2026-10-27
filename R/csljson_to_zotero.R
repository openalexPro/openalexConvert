#' Import CSL JSON files into Zotero
#'
#' @description
#' Import one or more CSL JSON files (e.g. the chunks written by
#' [corpus_to_csljson()]) into Zotero.
#'
#' - `method = "local"` sends the items to a running Zotero desktop app via
#'   its local connector endpoint
#'   (`/connector/import`, the endpoint the browser connector uses). Zotero's
#'   own CSL JSON importer does the mapping. Items go into the library or
#'   collection **currently selected in Zotero**; select a group library there
#'   to import into the group, and Zotero sync uploads them.
#' - `method = "web"` (headless upload via the Zotero Web API) is not
#'   implemented yet and raises an error.
#'
#' Zotero imports the CSL `note` into **Extra**; for files written by
#' [corpus_to_csljson()] its first line is the item's `OpenAlex: W...`.
#'
#' @section Items already in Zotero:
#' Before importing, the selected **library** (all of it, not only the selected
#' collection) is searched for items whose Extra holds an OpenAlex ID, in any
#' of the forms in use: `OpenAlex: W...` (written by this package),
#' `OpenAlex: https://openalex.org/W...` (Zotero's OpenAlex translators),
#' `openalex.work_id: W...` and `OpenAlex Work ID: W...` (two Zotero plugins).
#' Items whose OpenAlex ID is not found there (or that have none) are imported.
#' Items already there are handled by `existing`:
#'
#' - `"skip"` (default): left untouched and not imported.
#' - `"update"`: the existing Zotero item gets the new metadata; fields the
#'   new metadata does not have keep their old values.
#' - `"overwrite"`: all fields of the existing Zotero item are replaced by the
#'   new metadata; fields it does not have are emptied.
#'
#' With `"update"` and `"overwrite"` the existing item keeps its item key,
#' child notes and attachments, tags, collections and related items.
#' Technically, the items are imported with Zotero's CSL JSON importer, their
#' fields are copied onto the existing items, and the imported copies are
#' deleted again.
#'
#' @section Tags:
#' CSL JSON has no tags, so by default items arrive without tags, and existing
#' items keep theirs. With `tags` (e.g. the `zotero_tags.parquet` written by
#' [zotero_tags()]), tags are written by OpenAlex ID, following `existing`:
#'
#' - new items get the tags of their OpenAlex ID;
#' - `"skip"`: existing items are left untouched, tags included;
#' - `"update"`: tags missing on the existing item are added, its own are kept;
#' - `"overwrite"`: the existing item's tags are replaced by those in `tags`,
#'   and removed if `tags` has none for its OpenAlex ID.
#'
#' Rows of several libraries are merged; a tag keeps its type (manual or
#' automatic).
#'
#' @section Collection:
#' With `collection`, e.g. `c("my_project", "corpus_a")`, the works are also
#' put into that collection, nested from the top level of the selected
#' library (`my_project` > `corpus_a`). Missing collections are created,
#' existing ones of the same name reused, so a re-export goes into the same
#' collection. Works already in the library join the collection too, with
#' every value of `existing`: collections are independent of the item, and
#' one work can be in several. Other collections of an item are kept.
#'
#' New items also land in whatever is selected in Zotero, so select the
#' library itself (not a collection) to have them only in `collection`.
#' Deleting the collection in Zotero with its items removes an accidental
#' export again; items that were already in the library before stay in their
#' other collections.
#'
#' @section Write access:
#' `"update"`, `"overwrite"`, `tags` and `collection` write through Zotero's
#' local API,
#' which needs Zotero 10 or later and a key. If `api_key` is empty, Zotero shows a dialog asking to allow access for
#' "openalexConvert": choose **Always Allow** (a key allowed once is only good
#' for a single write). The key is kept for the rest of the R session.
#'
#' Progress is reported via the \pkg{progressr} package.
#'
#' @section Speed:
#' Zotero gets slower as the library grows. Measured with Zotero 10.0.6 on a
#' Mac, importing 5000 works in files of 1000 into a library starting at about
#' 440 items:
#'
#' | file | items in library before | time | works/s |
#' |---:|---:|---:|---:|
#' | 1 | 440 | 57 s | 17.5 |
#' | 2 | 1440 | 89 s | 11.2 |
#' | 3 | 2440 | 121 s | 8.3 |
#' | 4 | 3440 | 145 s | 6.9 |
#' | 5 | 4440 | 163 s | 6.1 |
#'
#' Zotero's memory use grew to 3.4 GB during that run. For 100000 works, plan
#' for several hours to more than a day, and consider restarting Zotero every
#' few files.
#'
#' The search for items already in the library (run once per call, for every
#' value of `existing`) took 0.2 s for 369 IDs and 6.6 s for 5369; it grows
#' faster than the library, so expect tens of minutes for 100000. Re-running
#' all 5000 works with `existing = "skip"` took 4.7 s, mostly that search.
#' [corpus_to_csljson()] itself takes about 1 ms per work.
#'
#' @param files Character vector. Paths to CSL JSON files. If a single element
#'   points to an existing directory, all `*.json` files in that directory
#'   (non-recursive) are used.
#' @param method `"local"` (default) or `"web"`. See Description.
#' @param existing `"skip"` (default), `"update"` or `"overwrite"`: what to do
#'   with items whose OpenAlex ID is already in the selected Zotero library.
#'   See "Items already in Zotero".
#' @param tags `NULL` (default: no tags written), or a data.frame or path to a
#'   parquet file with columns `openalex_id`, `tag` and optionally `type`
#'   (`0` manual, `1` automatic), such as the one written by [zotero_tags()].
#'   See "Tags".
#' @param collection `NULL` (default: only the target selected in Zotero), or
#'   the path of a collection to put the works in, e.g.
#'   `c("my_project", "corpus_a")`. See "Collection".
#' @param url Base URL of the local Zotero server. Default
#'   `"http://127.0.0.1:23119"`.
#' @param api_key Key for Zotero's local API, only needed for
#'   `existing = "update"` or `"overwrite"`, `tags` or `collection`. Defaults to
#'   `Sys.getenv("ZOTERO_LOCAL_API_KEY")`; if empty, Zotero is asked for one.
#' @param timeout Seconds to wait for Zotero to import one file. Default
#'   `3600`; a 10000-item chunk can take 10 to 30 minutes (see "Speed").
#'
#' @return
#' Invisibly, a data.frame with one row per file and columns:
#' \describe{
#'   \item{file}{Path to the CSL JSON file.}
#'   \item{status_code}{HTTP status code of the last import request (`201` on
#'     success, `NA` if nothing had to be imported).}
#'   \item{ok}{Logical; `TRUE` if every step for the file succeeded.}
#'   \item{n_items}{Number of new items imported.}
#'   \item{n_skipped}{Number of items skipped because they already exist.}
#'   \item{n_updated}{Number of existing Zotero items updated or overwritten.}
#'   \item{n_tagged}{Number of items whose tags were written from `tags`.}
#'   \item{message}{Character; error text if something failed.}
#' }
#'
#' @examples
#' \dontrun{
#' # In Zotero, select the target library or collection first.
#' res <- csljson_to_zotero("csljson")  # directory with chunk_1.json, ...
#' subset(res, !ok)
#'
#' # Re-export after the corpus was updated: refresh what is already there
#' csljson_to_zotero("csljson", existing = "update")
#' }
#'
#' @importFrom httr2 request req_url_path req_url_query req_body_raw
#' @importFrom httr2 req_body_json req_headers req_method req_error req_timeout
#' @importFrom httr2 req_perform resp_status resp_has_body resp_body_string
#' @importFrom httr2 resp_header
#' @importFrom progressr with_progress progressor
#' @md
#'
#' @export
csljson_to_zotero <- function(
  files,
  method = c("local", "web"),
  existing = c("skip", "update", "overwrite"),
  tags = NULL,
  collection = NULL,
  url = "http://127.0.0.1:23119",
  api_key = Sys.getenv("ZOTERO_LOCAL_API_KEY"),
  timeout = 3600
) {
  method <- match.arg(method)
  existing <- match.arg(existing)
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
  tag_index <- if (!is.null(tags)) .tag_index(tags)

  # Zotero must be running, and the selected target must accept new items
  target <- .zotero_selected(url)
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

  api <- .zotero_local_api(url, target$libraryName)
  index <- .zotero_openalex_index(api)
  if (length(index)) {
    message(length(index), " OpenAlex ID(s) already in this library")
  }
  if ((existing != "skip" && length(index)) || length(tag_index) || length(collection)) {
    api$key <- if (nzchar(api_key)) api_key else .zotero_local_key(api)
  }
  coll <- NULL
  if (length(collection)) {
    coll <- .zotero_collection(api, collection)
    message("Adding the works to collection ", paste(collection, collapse = " / "))
  }

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
        n_skipped = 0L,
        n_updated = 0L,
        n_tagged = 0L,
        message = ""
      )

      if (!file.exists(f)) {
        res$message <- "File does not exist"
        results[[i]] <- res
        next
      }
      items <- tryCatch(
        jsonlite::read_json(f, simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (is.null(items)) {
        res$message <- "Not a JSON file"
        results[[i]] <- res
        next
      }

      ids <- vapply(items, function(it) .csl_openalex_id(it$id), "")
      known <- nzchar(ids) & ids %in% names(index)
      res$ok <- TRUE
      if (existing == "skip") {
        res$n_skipped <- sum(known)
        if (!is.null(coll) && any(known)) {
          # collections are independent of the item: skipped works join too
          step <- tryCatch(
            .zotero_add_to_collection(api, unlist(unname(index[ids[known]]), recursive = FALSE), coll),
            error = function(e) list(n = 0L, message = conditionMessage(e))
          )
          res$ok <- !nzchar(step$message)
          res$message <- step$message
        }
        items <- items[!known]
        known <- known[!known]
      }

      if (any(!known) && res$ok) {
        imp <- .zotero_import(url, items[!known], paste0(session, "-", i), timeout)
        res$status_code <- imp$status_code
        res$ok <- imp$ok
        res$n_items <- length(imp$items)
        res$message <- imp$message
        if (imp$ok && (length(tag_index) || !is.null(coll))) {
          step <- tryCatch(
            .zotero_finish_new(api, imp$items, tag_index, coll),
            error = function(e) list(n = 0L, n_tagged = 0L, message = conditionMessage(e))
          )
          res$n_tagged <- step$n_tagged
          res$ok <- !nzchar(step$message)
          res$message <- step$message
        }
      }

      if (any(known) && res$ok) {
        imp <- .zotero_import(url, items[known], paste0(session, "-", i, "-u"), timeout)
        res$status_code <- imp$status_code
        step <- if (!imp$ok) {
          list(n = 0L, message = imp$message)
        } else {
          tryCatch(
            .zotero_update(api, imp$items, index, blank = existing == "overwrite", tag_index, coll),
            error = function(e) list(n = 0L, n_tagged = 0L, message = conditionMessage(e))
          )
        }
        res$n_updated <- step$n
        res$n_tagged <- res$n_tagged + (step$n_tagged %||% 0L)
        res$ok <- !nzchar(step$message)
        res$message <- step$message
      }

      results[[i]] <- res
    }
  })

  out <- do.call(rbind, lapply(results, as.data.frame))
  rownames(out) <- NULL
  invisible(out)
}


# -----------------------------------------------------------------------------
# Internal helpers (non-exported)
# -----------------------------------------------------------------------------

#' OpenAlex ID ("W...") from a CSL `id` such as "https://openalex.org/W123"
#'
#' @noRd
.csl_openalex_id <- function(id) {
  sub("^https?://openalex\\.org/", "", id %||% "", ignore.case = TRUE)
}

#' OpenAlex ID ("W123") from a Zotero Extra field, or NA
#'
#' Reads every form in use (key case-insensitive):
#' - `OpenAlex: W123` -- written by this package and the IPBES pipeline
#' - `OpenAlex: https://openalex.org/W123` -- Zotero's OpenAlex translators
#' - `openalex.work_id: W123` -- the zotero-openalex plugin
#' - `OpenAlex Work ID: W123` -- the open-alex-work-id plugin
#'
#' @noRd
.extra_openalex_id <- function(extra) {
  extra <- extra %||% ""
  m <- regmatches(extra, regexec(
    "(?im)^\\s*(?:openalex(?: work id)?|openalex\\.work_id)\\s*:\\s*(?:https?://(?:www\\.)?openalex\\.org/)?(w\\d+)\\s*$",
    extra,
    perl = TRUE
  ))[[1]]
  if (length(m)) toupper(m[[2]]) else NA_character_
}

#' Library/collection selected in Zotero; errors if Zotero is not running
#'
#' @noRd
.zotero_selected <- function(url) {
  tryCatch(
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
}

#' Send CSL items to Zotero's connector import
#'
#' Returns list(status_code, ok, items = the created Zotero items, message).
#'
#' @noRd
.zotero_import <- function(url, items, session, timeout) {
  out <- list(status_code = NA_integer_, ok = FALSE, items = list(), message = "")
  json <- jsonlite::toJSON(items, auto_unbox = TRUE, digits = NA, null = "null")
  resp <- try(
    httr2::request(url) |>
      httr2::req_url_path("/connector/import") |>
      httr2::req_url_query(session = session) |>
      # text/plain: with application/json Zotero parses the body itself and
      # the import translators never see the raw text
      httr2::req_body_raw(as.character(json), type = "text/plain") |>
      httr2::req_timeout(timeout) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    silent = TRUE
  )
  if (inherits(resp, "try-error")) {
    out$message <- as.character(resp)
    return(out)
  }
  out$status_code <- httr2::resp_status(resp)
  body <- if (httr2::resp_has_body(resp)) httr2::resp_body_string(resp) else ""
  if (out$status_code == 201L) {
    out$ok <- TRUE
    out$items <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  } else if (out$status_code == 400L) {
    out$message <- "Zotero found no importer for this file (not CSL JSON?)"
  } else {
    out$message <- substr(body, 1L, 500L)
  }
  out
}

#' Local API handle for the library selected in Zotero
#'
#' Group libraries are matched by name; anything else is the user library.
#'
#' @noRd
.zotero_local_api <- function(url, library_name) {
  resp <- httr2::request(url) |>
    httr2::req_url_path("/api/users/0/groups") |>
    httr2::req_perform()
  groups <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
  hit <- Filter(function(g) identical(g$data$name, library_name), groups)
  list(
    url = url,
    prefix = if (length(hit)) paste0("/api/groups/", hit[[1]]$id) else "/api/users/0",
    server_id = httr2::resp_header(resp, "Zotero-Server-ID"),
    key = NULL
  )
}

#' Request to the local API, with server ID and (if present) key
#'
#' @noRd
.zotero_local_req <- function(api, path) {
  req <- httr2::request(api$url) |>
    httr2::req_url_path(paste0(api$prefix, path)) |>
    httr2::req_headers(`Zotero-Server-ID` = api$server_id)
  if (!is.null(api$key)) {
    req <- httr2::req_headers(req, `Zotero-API-Key` = api$key)
  }
  req
}

#' All items in the library carrying "OpenAlex: W..." in Extra
#'
#' Returns a named list: OpenAlex ID -> list of Zotero item `data` objects
#' (usually one; more if the library already holds duplicates).
#'
#' @noRd
.zotero_openalex_index <- function(api) {
  index <- list()
  start <- 0L
  repeat {
    batch <- .zotero_local_req(api, "/items") |>
      httr2::req_url_query(
        q = "OpenAlex", qmode = "everything", format = "json",
        limit = 100L, start = start
      ) |>
      httr2::req_perform() |>
      httr2::resp_body_string() |>
      jsonlite::fromJSON(simplifyVector = FALSE)
    for (it in batch) {
      id <- .extra_openalex_id(it$data$extra)
      if (!is.na(id)) index[[id]] <- c(index[[id]], list(it$data))
    }
    start <- start + length(batch)
    if (length(batch) < 100L) break
  }
  index
}

# Key for the local API, kept for the R session
.zotero_env <- new.env(parent = emptyenv())

#' Ask Zotero (dialog) for a local API key
#'
#' @noRd
.zotero_local_key <- function(api) {
  if (!is.null(.zotero_env$key)) {
    return(.zotero_env$key)
  }
  message("Asking Zotero for write access: choose 'Always Allow' in the dialog.")
  resp <- httr2::request(api$url) |>
    httr2::req_url_path("/api/local/authorize") |>
    httr2::req_headers(`Zotero-Server-ID` = api$server_id) |>
    httr2::req_body_json(list(appName = "openalexConvert")) |>
    httr2::req_timeout(600) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()
  # status first: an error body may be plain text, not JSON
  body <- if (httr2::resp_status(resp) == 200L) jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE) else list()
  if (is.null(body$key)) {
    stop("Zotero did not grant write access (needed for existing = \"update\" or \"overwrite\", and for tags).", call. = FALSE)
  }
  if (!isTRUE(body$remember)) {
    stop(
      "Writing to Zotero needs several requests, but a key allowed once is good ",
      "for one only. Run again and choose 'Always Allow'.",
      call. = FALSE
    )
  }
  .zotero_env$key <- body$key
  body$key
}

#' The write that puts `new`'s metadata (just imported) onto `old` (existing)
#'
#' Keeps the old item's identity and organisation. With `blank = TRUE`
#' ("overwrite") text fields and creators that `new` lacks are emptied; with
#' `blank = FALSE` ("update") they keep their old values. `tags` (from
#' `.tag_index()`, `NULL` = leave tags alone) replace the old tags when
#' `blank`, else the ones missing are added.
#'
#' @noRd
.zotero_update_object <- function(new, old, blank, tags = NULL, coll = NULL) {
  keep <- c("key", "version", "dateAdded", "dateModified", "collections", "tags", "relations", "parentItem")
  upd <- new[setdiff(names(new), keep)]
  upd <- upd[!vapply(upd, function(v) identical(v, "") || identical(v, list()), NA)]
  if (blank) {
    for (nm in setdiff(names(old), c(names(upd), keep))) {
      if (is.character(old[[nm]]) && length(old[[nm]]) == 1L) upd[[nm]] <- ""
    }
    if (is.null(upd$creators) && length(old$creators)) upd$creators <- list()
  }
  if (!is.null(tags)) {
    if (blank) {
      upd$tags <- tags
    } else {
      have <- vapply(old$tags, function(t) t$tag, "")
      add <- Filter(function(t) !t$tag %in% have, tags)
      if (length(add)) upd$tags <- c(old$tags, add)
    }
  }
  if (!is.null(coll) && !coll %in% unlist(old$collections)) {
    upd$collections <- as.list(c(unlist(old$collections), coll))
  }
  upd$key <- old$key
  upd$version <- old$version
  upd
}

#' POST objects to the local API's /items in batches of 50
#'
#' With `key` and `version` set, each object updates that existing item.
#' Returns list(n = objects written, message = "" or error text).
#'
#' @noRd
.zotero_post_items <- function(api, objects) {
  n <- 0L
  failed <- character()
  for (batch in split(objects, ceiling(seq_along(objects) / 50L))) {
    resp <- .zotero_local_req(api, "/items") |>
      httr2::req_body_raw(
        as.character(jsonlite::toJSON(unname(batch), auto_unbox = TRUE, digits = NA, null = "null")),
        type = "application/json"
      ) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()
    if (httr2::resp_status(resp) != 200L) {
      stop("Writing to Zotero failed: ", substr(httr2::resp_body_string(resp), 1L, 500L), call. = FALSE)
    }
    body <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
    n <- n + length(body$success) + length(body$unchanged)
    failed <- c(failed, vapply(body$failed, function(x) x$message %||% "", ""))
  }
  list(n = n, message = paste(unique(failed), collapse = "; "))
}

#' Copy freshly imported items onto the existing ones, then delete the copies
#'
#' Returns list(n = items updated, n_tagged = items whose tags were written,
#' message = "" or error text).
#'
#' @noRd
.zotero_update <- function(api, imported, index, blank, tag_index = NULL, coll = NULL) {
  updates <- list()
  for (new in imported) {
    id <- .extra_openalex_id(new$extra)
    tags <- if (!is.null(tag_index)) c(list(), tag_index[[id]])
    for (old in index[[id]]) {
      updates[[length(updates) + 1L]] <- .zotero_update_object(new, old, blank, tags, coll)
    }
  }
  out <- .zotero_post_items(api, updates)
  out$n_tagged <- sum(vapply(updates, function(u) !is.null(u$tags), NA))

  # the imported copies served only as Zotero's mapping; remove them again
  keys <- vapply(imported, function(x) x$key, "")
  for (batch in split(keys, ceiling(seq_along(keys) / 50L))) {
    version <- .zotero_local_req(api, "/items") |>
      httr2::req_url_query(limit = 1L, format = "keys") |>
      httr2::req_perform() |>
      httr2::resp_header("Last-Modified-Version")
    resp <- .zotero_local_req(api, "/items") |>
      httr2::req_url_query(itemKey = paste(batch, collapse = ",")) |>
      httr2::req_headers(`If-Unmodified-Since-Version` = version) |>
      httr2::req_method("DELETE") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()
    if (httr2::resp_status(resp) != 204L) {
      out$message <- paste(c(
        if (nzchar(out$message)) out$message,
        paste("Could not delete temporary copies:", paste(batch, collapse = ","))
      ), collapse = "; ")
    }
  }
  out
}

#' Tags by OpenAlex ID: named list of Zotero tag objects list(tag, type)
#'
#' `tags` is a data.frame or parquet path with `openalex_id`, `tag` and
#' optionally `type`. A tag appears once per work; manual (0) wins over
#' automatic (1).
#'
#' @noRd
.tag_index <- function(tags) {
  if (is.character(tags)) tags <- as.data.frame(arrow::read_parquet(tags))
  stopifnot(all(c("openalex_id", "tag") %in% names(tags)))
  type <- as.integer(if (is.null(tags$type)) 0L else tags$type)
  tags <- data.frame(id = toupper(tags$openalex_id), tag = tags$tag, type = type)
  tags <- tags[order(tags$type), ]
  tags <- tags[!duplicated(tags[c("id", "tag")]) & nzchar(tags$tag), ]
  lapply(split(tags, tags$id), function(d) {
    Map(function(tag, type) if (type == 0L) list(tag = tag) else list(tag = tag, type = type), d$tag, d$type, USE.NAMES = FALSE)
  })
}

#' Write tags and collection onto items just imported
#'
#' Tags come from `tag_index` (the items have none yet); `coll` (a collection
#' key or NULL) is added to the collections the connector put them in.
#' Returns list(n = items written, n_tagged, message = "" or error text).
#'
#' @noRd
.zotero_finish_new <- function(api, imported, tag_index, coll = NULL) {
  tags_of <- function(it) tag_index[[.extra_openalex_id(it$extra)]]
  todo <- if (is.null(coll)) Filter(function(it) length(tags_of(it)), imported) else imported
  if (!length(todo)) {
    return(list(n = 0L, n_tagged = 0L, message = ""))
  }
  # the connector does not return item versions; the local API does
  current <- list()
  keys <- vapply(todo, function(it) it$key, "")
  for (batch in split(keys, ceiling(seq_along(keys) / 50L))) {
    items <- .zotero_local_req(api, "/items") |>
      httr2::req_url_query(itemKey = paste(batch, collapse = ","), format = "json", limit = 50L) |>
      httr2::req_perform() |>
      httr2::resp_body_string() |>
      jsonlite::fromJSON(simplifyVector = FALSE)
    for (it in items) current[[it$data$key]] <- it$data
  }
  objects <- lapply(todo, function(it) {
    obj <- list(key = it$key, version = current[[it$key]]$version)
    if (length(tags_of(it))) obj$tags <- tags_of(it)
    if (!is.null(coll)) {
      obj$collections <- as.list(union(unlist(current[[it$key]]$collections), coll))
    }
    obj
  })
  out <- .zotero_post_items(api, objects)
  out$n_tagged <- sum(vapply(objects, function(o) !is.null(o$tags), NA))
  out
}

#' Add existing items (their `data`, as in the index) to collection `coll`
#'
#' Returns list(n = items written, message = "" or error text).
#'
#' @noRd
.zotero_add_to_collection <- function(api, items, coll) {
  items <- items[!duplicated(vapply(items, function(it) it$key, ""))]
  todo <- Filter(function(it) !coll %in% unlist(it$collections), items)
  .zotero_post_items(api, lapply(todo, function(it) list(
    key = it$key,
    version = it$version,
    collections = as.list(c(unlist(it$collections), coll))
  )))
}

#' Key of the collection `path` (e.g. c("project", "corpus")), nested from
#' the library's top level; missing levels are created, existing ones reused.
#'
#' @noRd
.zotero_collection <- function(api, path) {
  all <- list()
  start <- 0L
  repeat {
    batch <- .zotero_local_req(api, "/collections") |>
      httr2::req_url_query(format = "json", limit = 100L, start = start) |>
      httr2::req_perform() |>
      httr2::resp_body_string() |>
      jsonlite::fromJSON(simplifyVector = FALSE)
    all <- c(all, lapply(batch, `[[`, "data"))
    start <- start + length(batch)
    if (length(batch) < 100L) break
  }
  parent <- FALSE
  for (name in path) {
    hit <- Filter(function(d) {
      identical(d$name, name) && identical(d$parentCollection, parent) && !isTRUE(d$deleted)
    }, all)
    if (length(hit)) {
      parent <- hit[[1]]$key
      next
    }
    resp <- .zotero_local_req(api, "/collections") |>
      httr2::req_body_raw(
        as.character(jsonlite::toJSON(list(list(name = name, parentCollection = parent)), auto_unbox = TRUE)),
        type = "application/json"
      ) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()
    # status first: an error body may be plain text, not JSON
    body <- if (httr2::resp_status(resp) == 200L) jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE) else list()
    if (!length(body$success)) {
      stop("Could not create Zotero collection '", name, "': ", substr(httr2::resp_body_string(resp), 1L, 500L), call. = FALSE)
    }
    parent <- body$success[[1]]
  }
  parent
}
