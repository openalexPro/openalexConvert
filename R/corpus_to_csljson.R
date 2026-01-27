#' Convert a corpus to CSL JSON (chunked)
#'
#' Maps an OpenAlex-like corpus (Arrow Dataset/Table or data.frame/tibble) to
#' CSL JSON items and writes them into chunked files. The function creates the
#' directory `output` (if not present) and writes files `chunk_1.json`,
#' `chunk_2.json`, ... inside that directory.
#'
#' This converter targets the most common OpenAlex field layout and is resilient
#' to missing columns by falling back to `NULL`/empty values in SQL. Mapping
#' includes: title, year, DOI, container-title (venue), volume/issue/pages,
#' authors (with basic given/family split and ORCID when present), URL/abstract,
#' publisher and ISSN, language, keywords (collapsed to a single string), and an
#' aggregated `note` with OA status and citation count. Records are processed in
#' DuckDB-backed chunks for low memory usage.
#'
#' @param project_dir Optional path to project directory. If provided, used to
#'   set default values for `corpus` and `output` parameters. Can be omitted if
#'   `corpus` and `output` are specified explicitly.
#' @param corpus Path to parquet dataset, parquet Dataset/Table (e.g., from
#'   `arrow::open_dataset()`) or a data.frame/tibble (e.g., from
#'   `dplyr::collect()`).
#' @param output Path to a directory to create and populate with chunked CSL
#'   JSON files (`chunk_1.json`, `chunk_2.json`, ...).
#' @param chunk_size Rows processed per chunk via DuckDB. Default: 10000.
#' @param overwrite Overwrite `output` if it exists. Default: FALSE.
#' @param verbose Print progress messages. Default: TRUE.
#'
#' @return Invisibly returns `normalizePath(output)`.
#'
#' @md
#'
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery
#' @importFrom duckdb duckdb duckdb_register_arrow
#'
#' @export
corpus_to_csljson <- function(
  project_dir,
  corpus = file.path(project_dir, "parquet"),
  output = file.path(project_dir, "csljson"),
  chunk_size = 10000,
  overwrite = FALSE,
  verbose = TRUE
) {
  if (missing(corpus) || is.null(corpus)) {
    stop("`corpus` must be provided.")
  }
  if (is.character(corpus)) {
    corpus <- arrow::open_dataset(corpus)
  }

  if (missing(output) || is.null(output)) {
    stop("`output` must be provided.")
  }
  if (file.exists(output)) {
    if (!overwrite) {
      stop("`output` exists. Set `overwrite = TRUE`.")
    }
    unlink(output, recursive = TRUE, force = TRUE)
  }
  dir.create(output, recursive = TRUE, showWarnings = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE),
    add = TRUE
  )

  arrow_obj <- if (inherits(corpus, "data.frame")) {
    arrow::as_arrow_table(corpus)
  } else {
    corpus
  }
  tryCatch(
    {
      duckdb::duckdb_register_arrow(con, "src", arrow_obj)
    },
    error = function(e) {
      duckdb::duckdb_register_arrow(con, "src", arrow::as_arrow_table(corpus))
    }
  )

  n_total <- tryCatch(
    {
      as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM src")$n[1])
    },
    error = function(e) NA_integer_
  )
  if (is.na(n_total) || n_total < 0) {
    stop("Could not determine number of records in corpus.")
  }

  # Prepare chunked output directory (already created above)

  # Build a robust SELECT that adapts to available columns
  cols <- colnames(DBI::dbGetQuery(con, "SELECT * FROM src LIMIT 0"))
  select_sql <- .build_select_sql(cols)

  wrote <- 0L
  n_chunks <- if (n_total == 0) 0L else ceiling(n_total / chunk_size)
  for (k in seq_len(n_chunks)) {
    offset <- (k - 1L) * chunk_size
    q <- sprintf(
      "%s LIMIT %d OFFSET %d",
      select_sql,
      as.integer(chunk_size),
      as.integer(offset)
    )
    df <- DBI::dbGetQuery(con, q)
    if (!nrow(df)) {
      next
    }

    items <- vector("list", nrow(df))
    for (i in seq_len(nrow(df))) {
      rec <- df[i, , drop = FALSE]
      items[[i]] <- .map_record_to_csl(rec)
    }

    # Write this chunk as its own CSL JSON array file
    chunk_file <- file.path(output, sprintf("chunk_%d.json", k))
    jsonlite::write_json(
      items,
      path = chunk_file,
      auto_unbox = TRUE,
      pretty = FALSE
    )
    wrote <- wrote + length(items)
    if (verbose) {
      message(sprintf(
        "Wrote %s (%d/%d records)",
        basename(chunk_file),
        wrote,
        n_total
      ))
    }
  }
  if (verbose) {
    message(
      "Done: ",
      wrote,
      " records across ",
      n_chunks,
      " files in ",
      normalizePath(output)
    )
  }
  invisible(normalizePath(output))
}


# -----------------------------------------------------------------------------
# Internal helpers (non-exported)
# -----------------------------------------------------------------------------

#' Build a SELECT statement mapping corpus fields to normalized columns
#'
#' Chooses expressions conditionally based on available columns. Used to drive
#' chunked extraction through DuckDB.
#'
#' @noRd
.build_select_sql <- function(cols) {
  has <- function(n) n %in% cols
  title_expr <- if (has("display_name")) {
    "display_name"
  } else if (has("title")) {
    "title"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  year_expr <- if (has("publication_year")) {
    "publication_year"
  } else {
    "CAST(NULL AS INTEGER)"
  }
  doi_expr <- if (has("doi")) "doi" else "CAST(NULL AS VARCHAR)"
  type_expr <- if (has("type")) "type" else "CAST(NULL AS VARCHAR)"
  venue_expr <- if (has("host_venue") && has("primary_location")) {
    "COALESCE(host_venue.display_name, primary_location.source.display_name)"
  } else if (has("host_venue")) {
    "host_venue.display_name"
  } else if (has("primary_location")) {
    "primary_location.source.display_name"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  venue_type_expr <- if (has("host_venue") && has("primary_location")) {
    "COALESCE(host_venue.type, primary_location.source.type)"
  } else if (has("host_venue")) {
    "host_venue.type"
  } else if (has("primary_location")) {
    "primary_location.source.type"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  publisher_expr <- if (has("host_venue") && has("primary_location")) {
    "COALESCE(host_venue.publisher, primary_location.source.host_organization_name)"
  } else if (has("host_venue")) {
    "host_venue.publisher"
  } else if (has("primary_location")) {
    "primary_location.source.host_organization_name"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  issn_l_expr <- if (has("host_venue") && has("primary_location")) {
    "COALESCE(host_venue.issn_l, primary_location.source.issn_l)"
  } else if (has("host_venue")) {
    "host_venue.issn_l"
  } else if (has("primary_location")) {
    "primary_location.source.issn_l"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  issns_expr <- if (has("host_venue") && has("primary_location")) {
    "COALESCE(host_venue.issn, primary_location.source.issn)"
  } else if (has("host_venue")) {
    "host_venue.issn"
  } else if (has("primary_location")) {
    "primary_location.source.issn"
  } else {
    "[]"
  }
  volume_expr <- if (has("biblio")) "biblio.volume" else "CAST(NULL AS VARCHAR)"
  issue_expr <- if (has("biblio")) "biblio.issue" else "CAST(NULL AS VARCHAR)"
  fpage_expr <- if (has("biblio")) {
    "biblio.first_page"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  lpage_expr <- if (has("biblio")) {
    "biblio.last_page"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  url_expr <- {
    options <- c(
      if (has("doi_url")) "doi_url" else NULL,
      if (has("open_access")) "open_access.oa_url" else NULL,
      if (has("primary_location")) {
        "primary_location.landing_page_url"
      } else {
        NULL
      },
      if (has("id")) "id" else NULL
    )
    if (length(options) == 0) {
      "CAST(NULL AS VARCHAR)"
    } else {
      paste0("COALESCE(", paste(options, collapse = ", "), ")")
    }
  }
  abstract_expr <- if (has("abstract")) {
    "try_cast(abstract AS VARCHAR)"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  language_expr <- if (has("language")) "language" else "CAST(NULL AS VARCHAR)"
  pubdate_expr <- if (has("publication_date")) {
    "publication_date"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  authors_expr <- if (has("authorships")) {
    "list_transform(authorships, x -> COALESCE(x.author.display_name, x.raw_author_name))"
  } else {
    "[]"
  }
  orcids_expr <- if (has("authorships")) {
    "list_transform(authorships, x -> x.author.orcid)"
  } else {
    "[]"
  }
  keywords_expr <- if (has("concepts")) {
    "list_transform(concepts, x -> x.display_name)"
  } else {
    "[]"
  }
  oa_is_expr <- if (has("open_access")) {
    "open_access.is_oa"
  } else {
    "CAST(NULL AS BOOLEAN)"
  }
  oa_status_expr <- if (has("open_access")) {
    "open_access.oa_status"
  } else {
    "CAST(NULL AS VARCHAR)"
  }
  cited_by_expr <- if (has("cited_by_count")) {
    "cited_by_count"
  } else {
    "CAST(NULL AS INTEGER)"
  }

  # Optional ISBN (disabled by default as nested paths may not exist)
  isbn_expr <- "CAST(NULL AS VARCHAR)"

  paste0(
    "SELECT\n",
    "  ",
    if (has("id")) "id" else "CAST(NULL AS VARCHAR) AS id",
    ",\n",
    "  ",
    title_expr,
    " AS title,\n",
    "  ",
    year_expr,
    " AS year,\n",
    "  ",
    doi_expr,
    " AS doi,\n",
    "  ",
    type_expr,
    " AS type,\n",
    "  ",
    venue_expr,
    " AS venue,\n",
    "  ",
    venue_type_expr,
    " AS venue_type,\n",
    "  ",
    volume_expr,
    " AS volume,\n",
    "  ",
    issue_expr,
    " AS number,\n",
    "  ",
    fpage_expr,
    " AS first_page,\n",
    "  ",
    lpage_expr,
    " AS last_page,\n",
    "  ",
    url_expr,
    " AS url,\n",
    "  ",
    abstract_expr,
    " AS abstract,\n",
    "  ",
    authors_expr,
    " AS authors,\n",
    "  ",
    orcids_expr,
    " AS author_orcids,\n",
    "  ",
    publisher_expr,
    " AS publisher,\n",
    "  ",
    issn_l_expr,
    " AS issn_l,\n",
    "  ",
    issns_expr,
    " AS issns,\n",
    "  ",
    language_expr,
    " AS language,\n",
    "  ",
    pubdate_expr,
    " AS publication_date,\n",
    "  ",
    oa_is_expr,
    " AS is_oa,\n",
    "  ",
    oa_status_expr,
    " AS oa_status,\n",
    "  ",
    keywords_expr,
    " AS keywords,\n",
    "  ",
    cited_by_expr,
    " AS cited_by_count,\n",
    "  ",
    isbn_expr,
    " AS isbn\n",
    "FROM src"
  )
}

#' Split a person name into given/family with simple rules
#'
#' Accepts either "Family, Given" or space-separated strings, taking the last
#' token as family name.
#'
#' @noRd
.split_name <- function(name) {
  if (is.null(name) || is.na(name) || !nzchar(name)) {
    return(list(given = "", family = ""))
  }
  if (grepl(",", name, fixed = TRUE)) {
    fam <- trimws(sub(",.*$", "", name))
    giv <- trimws(sub("^[^,]*,", "", name))
    return(list(given = giv, family = fam))
  }
  parts <- strsplit(name, "\\s+")[[1]]
  parts <- parts[nzchar(parts)]
  if (!length(parts)) {
    return(list(given = "", family = ""))
  }
  family <- parts[length(parts)]
  given <- if (length(parts) > 1) {
    paste(parts[1:(length(parts) - 1)], collapse = " ")
  } else {
    ""
  }
  list(given = given, family = family)
}

#' Coalesce scalar-like values (preferring left-hand side)
#'
#' Treats NULL/length-0/NA/empty-string as missing.
#'
#' @noRd
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || is.na(a) || !nzchar(as.character(a))) {
    b
  } else {
    a
  }
}

#' Normalize DOI string to bare DOI
#'
#' Strips resolver prefixes; falls back to regex if package helper fails.
#'
#' @noRd
.normalize_doi <- function(doi_raw) {
  if (is.null(doi_raw) || !nzchar(doi_raw)) {
    return("")
  }
  doi_raw <- as.character(doi_raw)
  tryCatch(
    extract_doi(doi_raw, non_doi_value = "", normalize = TRUE, what = "doi"),
    error = function(e) sub("^(?i)https?://(dx\\.)?doi\\.org/", "", doi_raw)
  )
}

#' Infer CSL type from OpenAlex-like hints
#'
#' @noRd
.infer_csl_type <- function(
  t,
  vt,
  has_isbn,
  has_issn,
  has_container,
  has_vol_issue
) {
  t <- tolower(paste(t, collapse = " "))
  vt <- tolower(paste(vt, collapse = " "))

  map_type <- function(x) {
    if (!nzchar(x)) {
      return(NULL)
    }
    if (grepl("book[- ]chapter|chapter", x)) {
      return("chapter")
    }
    if (grepl("book|monograph", x)) {
      return("book")
    }
    if (grepl("proceedings[- ]article|conference[- ]paper|proceedings", x)) {
      return("paper-conference")
    }
    if (grepl("posted-content|preprint|manuscript", x)) {
      return("manuscript")
    }
    if (grepl("dissertation|thesis", x)) {
      return("thesis")
    }
    if (
      grepl(
        "report|working[ -]?paper|policy[- ]research[- ]working[- ]paper",
        x
      )
    ) {
      return("report")
    }
    if (grepl("dataset", x)) {
      return("dataset")
    }
    if (grepl("journal[- ]article|journal", x)) {
      return("article-journal")
    }
    NULL
  }

  csl <- map_type(t)
  if (is.null(csl)) {
    if (grepl("conference|proceedings", vt)) {
      csl <- "paper-conference"
    } else if (grepl("journal", vt)) {
      csl <- "article-journal"
    } else if (grepl("book", vt)) {
      csl <- "book"
    }
  }

  # ISBN/ISSN overrides
  if (!is.null(csl)) {
    if (isTRUE(has_isbn) && csl %in% c("article-journal", "manuscript")) {
      csl <- "book"
    }
    if (isTRUE(has_issn) && csl %in% c("book")) csl <- "article-journal"
  }

  if (is.null(csl)) {
    if (isTRUE(has_container) && isTRUE(has_vol_issue)) csl <- "article-journal"
  }
  if (is.null(csl)) {
    csl <- "article-journal"
  }
  csl
}

#' Sanitize a CSL-JSON-like list recursively
#'
#' - Drops NULL and NA scalars
#' - Normalizes character encoding to UTF-8 and strips control characters
#' - Truncates abstract to 700 chars
#' - Cleans author sublists (removes empty fields / NA ORCID)
#'
#' @noRd
.sanitize_csl_item <- function(x) {
  if (is.list(x)) {
    out <- list()
    for (nm in names(x)) {
      val <- x[[nm]]
      if (is.null(val)) {
        next
      }
      if (is.atomic(val) && length(val) == 1 && is.na(val)) {
        next
      }
      if (identical(nm, "abstract") && is.character(val) && length(val)) {
        val[is.na(val)] <- ""
        val <- substr(val, 1L, 700L)
      }
      if (nm == "author" && is.list(val)) {
        auths <- list()
        for (a in val) {
          if (!is.list(a)) {
            next
          }
          if (
            !is.null(a$ORCID) && (is.na(a$ORCID) || identical(a$ORCID, "NA"))
          ) {
            a$ORCID <- NULL
          }

          if (!is.null(a$given) && is.na(a$given)) {
            a$given <- ""
          }
          if (!is.null(a$family) && is.na(a$family)) {
            a$family <- ""
          }
          auths[[length(auths) + 1L]] <- a
        }
        out$author <- auths
        next
      }
      out[[nm]] <- .sanitize_csl_item(val)
    }
    return(out)
  }
  if (is.atomic(x)) {
    if (is.character(x)) {
      x[is.na(x)] <- ""
      x <- tryCatch(
        suppressWarnings(iconv(x, from = "", to = "UTF-8", sub = "")),
        error = function(e) x
      )
      x <- gsub("[[:cntrl:]]", " ", x, perl = TRUE)
      x <- gsub("\\s+", " ", x, perl = TRUE)
      x <- trimws(x)
    } else if (is.logical(x)) {
      x[is.na(x)] <- FALSE
    }
  }
  x
}

#' Map a single DB record row to a CSL item
#'
#' Expects a 1-row data.frame produced by the SELECT from `.build_select_sql`.
#'
#' @noRd
.map_record_to_csl <- function(rec) {
  pages <- if (
    !is.na(rec$first_page) &&
      nzchar(rec$first_page) &&
      !is.na(rec$last_page) &&
      nzchar(rec$last_page)
  ) {
    paste0(rec$first_page, "-", rec$last_page)
  } else {
    ""
  }

  t <- rec$type %||% ""
  vt <- rec$venue_type %||% ""
  has_isbn <- !is.null(rec$isbn) && nzchar(as.character(rec$isbn))
  has_issn <- (!is.null(rec$issn_l) && nzchar(rec$issn_l)) ||
    (!is.null(rec$issns[[1]]) && length(rec$issns[[1]]) > 0)
  has_container <- nzchar(rec$venue %||% "")
  has_vol_issue <- nzchar(rec$volume %||% "") || nzchar(rec$number %||% "")
  csl_type <- .infer_csl_type(
    t,
    vt,
    has_isbn,
    has_issn,
    has_container,
    has_vol_issue
  )

  # Authors with optional ORCID
  auths <- list()
  orcids <- if (!is.null(rec$author_orcids[[1]])) {
    as.character(rec$author_orcids[[1]])
  } else {
    NULL
  }
  if (!is.null(rec$authors[[1]])) {
    for (idx in seq_along(rec$authors[[1]])) {
      nm <- as.character(rec$authors[[1]][[idx]])
      sp <- .split_name(nm)
      a <- list(given = sp$given, family = sp$family)
      if (!is.null(orcids) && idx <= length(orcids) && nzchar(orcids[[idx]])) {
        a$ORCID <- orcids[[idx]]
      }
      auths[[length(auths) + 1L]] <- a
    }
  }

  # issued date-parts
  issued_parts <- NULL
  if (!is.null(rec$publication_date) && nzchar(rec$publication_date)) {
    dp <- strsplit(as.character(rec$publication_date), "-")[[1]]
    nums <- suppressWarnings(as.integer(dp))
    nums <- nums[!is.na(nums)]
    if (length(nums) >= 1) issued_parts <- as.list(nums)
  }
  if (is.null(issued_parts)) {
    issued_parts <- as.list(stats::na.omit(as.integer(rec$year)))
  }

  # keywords
  keyword_val <- NULL
  if (!is.null(rec$keywords[[1]]) && length(rec$keywords[[1]]) > 0) {
    kw <- as.character(rec$keywords[[1]])
    kw <- kw[nzchar(kw)]
    if (length(kw)) keyword_val <- paste(kw, collapse = "; ")
  }

  # ISSN
  issn_val <- if (!is.null(rec$issn_l) && nzchar(rec$issn_l)) {
    rec$issn_l
  } else if (!is.null(rec$issns[[1]]) && length(rec$issns[[1]]) > 0) {
    paste(as.character(rec$issns[[1]]), collapse = ",")
  } else {
    ""
  }

  # Note field aggregating OA/citation info
  note_val <- NULL
  if (
    !is.null(rec$is_oa) ||
      !is.null(rec$oa_status) ||
      !is.null(rec$cited_by_count)
  ) {
    parts_note <- c()
    if (!is.null(rec$is_oa) && !is.na(rec$is_oa)) {
      parts_note <- c(parts_note, paste0("OA:", as.character(rec$is_oa)))
    }
    if (!is.null(rec$oa_status) && nzchar(rec$oa_status)) {
      parts_note <- c(parts_note, paste0("OA_status:", rec$oa_status))
    }
    if (!is.null(rec$cited_by_count) && !is.na(rec$cited_by_count)) {
      parts_note <- c(parts_note, paste0("Citations:", rec$cited_by_count))
    }
    if (length(parts_note)) note_val <- paste(parts_note, collapse = "; ")
  }

  it <- list(type = csl_type, id = rec$id %||% "", title = rec$title %||% "")
  if (length(auths)) {
    it$author <- auths
  }
  if (!is.null(issued_parts) && length(issued_parts) > 0) {
    it$issued <- list("date-parts" = list(issued_parts))
  }
  if (nzchar(rec$venue %||% "")) {
    it[["container-title"]] <- rec$venue
  }
  if (nzchar(rec$volume %||% "")) {
    it$volume <- rec$volume
  }
  if (nzchar(rec$number %||% "")) {
    it$issue <- rec$number
  }
  if (nzchar(pages)) {
    it$page <- pages
  }

  # DOI and URL
  if (nzchar(rec$doi %||% "")) {
    doi_norm <- .normalize_doi(rec$doi %||% "")
    if (nzchar(doi_norm)) it$DOI <- doi_norm
  }
  if (nzchar(rec$url %||% "")) {
    url_val <- as.character(rec$url)
    if (
      !("DOI" %in%
        names(it) &&
        grepl("^(?i)https?://(dx\\.)?doi\\.org/", url_val))
    ) {
      it$URL <- url_val
    }
  }

  if (nzchar(rec$abstract %||% "")) {
    it$abstract <- rec$abstract
  }
  if (nzchar(rec$publisher %||% "")) {
    it$publisher <- rec$publisher
  }
  if (nzchar(issn_val)) {
    it$ISSN <- issn_val
  }
  if (nzchar(rec$language %||% "")) {
    it$language <- rec$language
  }
  if (!is.null(keyword_val)) {
    it$keyword <- keyword_val
  }
  if (!is.null(note_val)) {
    it$note <- note_val
  }
  if (csl_type %in% c("book", "chapter", "report")) {
    if (!is.null(rec$isbn) && nzchar(as.character(rec$isbn))) {
      it$ISBN <- as.character(rec$isbn)
    }
  }

  .sanitize_csl_item(it)
}
