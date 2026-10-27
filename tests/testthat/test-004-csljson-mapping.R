# Unit tests for the corpus -> CSL JSON mapping helpers in corpus_to_csljson.R.
# Everything here runs offline on tiny in-memory inputs.

# One row as produced by the SELECT from .build_select_sql(), every field
# missing unless given in `...` (list columns: wrap the value in list()).
csl_rec <- function(...) {
  rec <- list(
    id = NA_character_, title = NA_character_, year = NA_integer_,
    doi = NA_character_, type = NA_character_, venue = NA_character_,
    venue_type = NA_character_, volume = NA_character_, number = NA_character_,
    first_page = NA_character_, last_page = NA_character_, url = NA_character_,
    abstract = NA_character_, authors = list(NULL), author_orcids = list(NULL),
    publisher = NA_character_, issn_l = NA_character_, issns = list(NULL),
    language = NA_character_, publication_date = NA_character_, is_oa = NA,
    oa_status = NA_character_, keywords = list(NULL),
    cited_by_count = NA_integer_, isbn = NA_character_
  )
  args <- list(...)
  rec[names(args)] <- args
  structure(rec, class = "data.frame", row.names = 1L)
}

test_that(".build_select_sql falls back to typed NULLs for missing columns", {
  sql <- .build_select_sql(character())
  expect_false(grepl("display_name|host_venue|primary_location|biblio", sql))
  expect_match(sql, "CAST(NULL AS VARCHAR) AS id", fixed = TRUE)
  expect_match(sql, "CAST(NULL AS VARCHAR) AS title", fixed = TRUE)
  expect_match(sql, "CAST(NULL AS INTEGER) AS year", fixed = TRUE)
  expect_match(sql, "CAST(NULL AS VARCHAR) AS url", fixed = TRUE)
  expect_match(sql, "[] AS authors", fixed = TRUE)

  # ... and the statement is valid SQL returning every expected column
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE src AS SELECT 1 AS dummy")
  res <- DBI::dbGetQuery(con, sql)
  expect_equal(nrow(res), 1L)
  expect_named(res, c(
    "id", "title", "year", "doi", "type", "venue", "venue_type", "volume",
    "number", "first_page", "last_page", "url", "abstract", "authors",
    "author_orcids", "publisher", "issn_l", "issns", "language",
    "publication_date", "is_oa", "oa_status", "keywords", "cited_by_count",
    "isbn"
  ))
})

test_that(".build_select_sql uses `title` and `host_venue` when present", {
  sql <- .build_select_sql(c("title", "host_venue"))
  expect_match(sql, "\n  title AS title,", fixed = TRUE)
  expect_match(sql, "host_venue.display_name AS venue", fixed = TRUE)
  expect_match(sql, "host_venue.type AS venue_type", fixed = TRUE)
  expect_match(sql, "host_venue.publisher AS publisher", fixed = TRUE)
  expect_match(sql, "host_venue.issn_l AS issn_l", fixed = TRUE)
  expect_match(sql, "host_venue.issn AS issns", fixed = TRUE)
  expect_false(grepl("primary_location|COALESCE", sql))

  both <- .build_select_sql(c("host_venue", "primary_location"))
  expect_match(
    both,
    "COALESCE(host_venue.display_name, primary_location.source.display_name)",
    fixed = TRUE
  )
})

test_that("corpus_to_csljson accepts a data.frame and maps CSL types", {
  df <- data.frame(
    id = c("https://openalex.org/W1", "https://openalex.org/W2"),
    title = c("A dataset", "A paper"),
    type = c("dataset", "proceedings-article")
  )
  out <- tempfile("csl_")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  msgs <- capture_messages(
    res <- corpus_to_csljson(corpus = df, output = out, verbose = TRUE)
  )
  # match anywhere: duckdb may add its own one-time notice first
  expect_match(msgs, "Wrote chunk_1.json (2/2 records)", fixed = TRUE, all = FALSE)
  expect_match(msgs, "Done: 2 records across 1 files", fixed = TRUE, all = FALSE)
  expect_identical(res, normalizePath(out))
  items <- jsonlite::read_json(file.path(out, "chunk_1.json"))
  expect_equal(vapply(items, `[[`, "", "type"), c("dataset", "paper-conference"))
  expect_equal(vapply(items, `[[`, "", "title"), c("A dataset", "A paper"))
  # without doi_url/open_access/landing page the OpenAlex id is the URL
  expect_equal(vapply(items, `[[`, "", "URL"), df$id)
  expect_match(items[[1]]$note, "^OpenAlex: W1")
})

test_that("corpus_to_csljson writes no chunk for an empty corpus", {
  out <- tempfile("csl_")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  df <- data.frame(id = character(), title = character())
  expect_message(
    corpus_to_csljson(corpus = df, output = out),
    "Done: 0 records across 0 files"
  )
  expect_true(dir.exists(out))
  expect_length(list.files(out), 0L)
})

test_that("corpus_export_via_pandoc errors when the corpus yields no chunks", {
  df <- data.frame(id = character(), title = character())
  expect_error(
    corpus_export_via_pandoc(df, tempfile(fileext = ".bib"), verbose = FALSE),
    "No CSL JSON chunks were produced"
  )
})

test_that("corpus_to_csljson requires `output`", {
  expect_error(
    corpus_to_csljson(corpus = data.frame(id = "W1")),
    "`output` must be provided"
  )
})

test_that("corpus_to_csljson errors when the record count is unavailable", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(...) stop("no such table"),
    .package = "DBI"
  )
  out <- tempfile("csl_")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  expect_error(
    corpus_to_csljson(corpus = data.frame(id = "W1"), output = out),
    "Could not determine number of records"
  )
})

test_that("corpus_to_csljson retries registration as an Arrow table", {
  real <- duckdb::duckdb_register_arrow
  seen <- list()
  testthat::local_mocked_bindings(
    duckdb_register_arrow = function(conn, name, arrow_scannable, ...) {
      seen[[length(seen) + 1L]] <<- class(arrow_scannable)
      if (length(seen) == 1L) stop("cannot scan this object")
      real(conn, name, arrow_scannable, ...)
    },
    .package = "duckdb"
  )
  out <- tempfile("csl_")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  corpus_to_csljson(
    corpus = data.frame(id = "https://openalex.org/W1", title = "T"),
    output = out,
    verbose = FALSE
  )
  expect_length(seen, 2L)
  expect_true("Table" %in% seen[[2]])
  expect_equal(jsonlite::read_json(file.path(out, "chunk_1.json"))[[1]]$title, "T")
})

test_that(".split_name handles empty, 'Family, Given' and plain names", {
  empty <- list(given = "", family = "")
  expect_equal(.split_name(NULL), empty)
  expect_equal(.split_name(NA_character_), empty)
  expect_equal(.split_name(""), empty)
  expect_equal(.split_name("   "), empty)
  expect_equal(
    .split_name("Curie, Marie Salomea"),
    list(given = "Marie Salomea", family = "Curie")
  )
  expect_equal(
    .split_name("Marie Salomea Curie"),
    list(given = "Marie Salomea", family = "Curie")
  )
  expect_equal(.split_name("Plato"), list(given = "", family = "Plato"))
})

test_that(".normalize_doi returns '' for a missing DOI", {
  expect_identical(.normalize_doi(NULL), "")
  expect_identical(.normalize_doi(""), "")
})

test_that(".infer_csl_type maps OpenAlex types and venue hints", {
  type <- function(t = "", vt = "", isbn = FALSE, issn = FALSE,
                   container = FALSE, vol = FALSE) {
    .infer_csl_type(t, vt, isbn, issn, container, vol)
  }
  expect_equal(type("book-chapter"), "chapter")
  expect_equal(type("monograph"), "book")
  expect_equal(type("proceedings-article"), "paper-conference")
  expect_equal(type("preprint"), "manuscript")
  expect_equal(type("dissertation"), "thesis")
  expect_equal(type("working paper"), "report")
  expect_equal(type("dataset"), "dataset")
  expect_equal(type("journal-article"), "article-journal")

  # unknown or empty type: fall back to the venue type
  expect_equal(type("", "conference"), "paper-conference")
  expect_equal(type("other", "journal"), "article-journal")
  expect_equal(type("", "book series"), "book")

  # ISBN turns articles/manuscripts into books, ISSN turns books into articles
  expect_equal(type("preprint", isbn = TRUE), "book")
  expect_equal(type("monograph", issn = TRUE), "article-journal")

  # nothing known: container + volume/issue, or the default
  expect_equal(type("", "", container = TRUE, vol = TRUE), "article-journal")
  expect_equal(type("", ""), "article-journal")
})

test_that(".sanitize_csl_item drops missing values and cleans authors", {
  x <- list(
    title = "  A\ttitle  ",
    empty = NULL,
    missing = NA,
    flags = c(TRUE, NA),
    author = list(
      "not a person",
      list(given = NA, family = "Doe", ORCID = "NA"),
      list(given = "Jane", family = NA, ORCID = NA)
    ),
    note = "OpenAlex: W1\nOA:TRUE"
  )
  out <- .sanitize_csl_item(x)
  expect_named(out, c("title", "flags", "author", "note"))
  expect_equal(out$title, "A title")
  expect_equal(out$flags, c(TRUE, FALSE))
  expect_equal(out$author, list(
    list(given = "", family = "Doe"),
    list(given = "Jane", family = "")
  ))
  expect_equal(out$note, "OpenAlex: W1\nOA:TRUE")
})

test_that(".map_record_to_csl maps a full record", {
  rec <- csl_rec(
    id = "https://openalex.org/W42", title = "Title", type = "journal-article",
    venue = "Journal", volume = "3", number = "2", first_page = "10",
    last_page = "20", doi = "https://doi.org/10.1234/abc",
    url = "https://doi.org/10.1234/abc", abstract = "Abstract.",
    authors = list(c("Ada Lovelace", "Babbage, Charles")),
    author_orcids = list(c("https://orcid.org/0000-0001", "")),
    publisher = "Pub", issn_l = "", issns = list(c("1111-1111", "2222-2222")),
    language = "en", is_oa = TRUE, oa_status = "gold", cited_by_count = 7L,
    keywords = list(c("ecology", "", "birds"))
  )
  it <- .map_record_to_csl(rec)
  expect_equal(it$type, "article-journal")
  expect_equal(it$`container-title`, "Journal")
  expect_equal(it$volume, "3")
  expect_equal(it$issue, "2")
  expect_equal(it$page, "10-20")
  expect_equal(it$DOI, "10.1234/abc")
  expect_null(it$URL) # the DOI resolver URL is redundant with DOI
  expect_equal(it$ISSN, "1111-1111,2222-2222")
  expect_equal(it$keyword, "ecology; birds")
  expect_equal(it$author, list(
    list(given = "Ada", family = "Lovelace", ORCID = "https://orcid.org/0000-0001"),
    list(given = "Charles", family = "Babbage")
  ))
  expect_equal(it$note, "OpenAlex: W42\nOA:TRUE; OA_status:gold; Citations:7")
})

test_that(".map_record_to_csl copies the ISBN for books only", {
  # issn_l = "": no ISSN (an NA issn_l hits the known bug below)
  rec <- function(type) csl_rec(id = "W1", type = type, isbn = "978-3", issn_l = "")
  book <- .map_record_to_csl(rec("book"))
  expect_equal(book$type, "book")
  expect_equal(book$ISBN, "978-3")
  # an ISBN turns a preprint into a book
  expect_equal(.map_record_to_csl(rec("preprint"))$type, "book")
  expect_null(.map_record_to_csl(rec("dataset"))$ISBN)
  # a real ISSN turns a book (series volume) into an article
  expect_equal(
    .map_record_to_csl(csl_rec(id = "W1", type = "book", issn_l = "1111-1111"))$type,
    "article-journal"
  )
})

test_that("books and preprints without ISBN/ISSN keep their CSL type", {
  # DuckDB returns missing values as NA, as in csl_rec()
  expect_equal(.map_record_to_csl(csl_rec(id = "W1", type = "book"))$type, "book")
  expect_equal(.map_record_to_csl(csl_rec(id = "W1", type = "preprint"))$type, "manuscript")
  # with a missing ISSN-L the ISSN falls back to the list of ISSNs
  expect_equal(
    .map_record_to_csl(csl_rec(id = "W1", issns = list(c("1111-1111", "2222-2222"))))$ISSN,
    "1111-1111,2222-2222"
  )
})

test_that(".map_record_to_csl builds issued from the date, else the year", {
  # before sanitizing: .sanitize_csl_item() is tested separately
  testthat::local_mocked_bindings(.sanitize_csl_item = function(x) x)
  dated <- .map_record_to_csl(csl_rec(publication_date = "2020-05-17", year = 2020L))
  expect_equal(dated$issued, list(`date-parts` = list(list(2020L, 5L, 17L))))
  undated <- .map_record_to_csl(csl_rec(publication_date = "", year = 2021L))
  expect_equal(undated$issued, list(`date-parts` = list(list(2021L))))
  neither <- .map_record_to_csl(csl_rec(publication_date = "", year = NA_integer_))
  expect_null(neither$issued)
})

test_that("issued date-parts survive into the written CSL JSON", {
  it <- .map_record_to_csl(csl_rec(id = "W1", publication_date = "2020-05-17"))
  expect_equal(it$issued, list(`date-parts` = list(list(2020L, 5L, 17L))))
})

test_that("a missing OA status is left out of the note", {
  it <- .map_record_to_csl(csl_rec(id = "W1", is_oa = TRUE, oa_status = NA_character_))
  expect_equal(it$note, "OpenAlex: W1\nOA:TRUE")
})
