# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`openalexConvert` is an R package that converts an OpenAlex parquet/Arrow corpus
(as produced by the sibling package [openalexPro](https://github.com/rkrug/openalexPro))
into bibliography formats. It is part of the `openalexPro` ecosystem (alongside
`openalexSnowball`) and is distributed via r-universe (`https://rkrug.r-universe.dev`),
not CRAN. Status is alpha (see the startup message in `R/zzz.R`).

## Commands

All commands assume the package root and use R's standard tooling.

```r
# Run the full test suite
devtools::test()

# Run a single test file
testthat::test_file("tests/testthat/test-001-corpus_csl_pandoc.R")

# Regenerate man/*.Rd and NAMESPACE from roxygen2 comments (required after
# changing @export tags or @param docs — NAMESPACE is generated, never hand-edit)
devtools::document()

# Full R CMD check
devtools::check()

# Render the pkgdown site locally
pkgdown::build_site()
```

CI (`.github/workflows/`) runs `R-CMD-check` on macOS/Windows/Ubuntu ×
devel/release/oldrel-1, plus `test-coverage` and `pkgdown`. Because `openalexPro`
lives on r-universe, `Additional_repositories` in `DESCRIPTION` must list it or
dependency resolution fails in CI.

## Architecture

The package is a thin pipeline with two stages. Each exported function is one
self-contained file in `R/`.

1. **Corpus → CSL JSON** ([R/corpus_to_csljson.R](R/corpus_to_csljson.R)):
   `corpus_to_csljson()` reads an Arrow Dataset/Table/data.frame, registers it
   with DuckDB (`duckdb_register_arrow`), and processes it in chunks of
   `chunk_size` rows via `LIMIT/OFFSET`. Output is one `chunk_N.json` file per
   chunk, each a CSL JSON array. This is the memory-efficient core — large
   corpora never load fully into R.

2. **CSL JSON → everything else** ([R/csljson_convert_pandoc.R](R/csljson_convert_pandoc.R)):
   `csljson_convert_pandoc()` shells out to Pandoc (via `rmarkdown::pandoc_convert`)
   to produce bibtex, biblatex, docx, markdown, latex, html, or pdf. It dispatches
   on whether the input is a directory of chunks or a single file, crossed with
   whether `to` is a bibliography format (`bibtex`/`biblatex`, direct conversion)
   or a formatted-document format (renders via citeproc with a generated
   `nocite: "@*"` markdown stub).

`corpus_export_via_pandoc()` ([R/corpus_export_via_pandoc.R](R/corpus_export_via_pandoc.R))
is a convenience wrapper chaining stage 1 → stage 2 through a temp dir.

`csljson_to_zotero_upload()` ([R/csljson_to_zotero_upload.R](R/csljson_to_zotero_upload.R))
is independent of the above: it POSTs CSL JSON files to the Zotero Web API
(`/groups/{id}/items`) using `httr2`, with `progressr` progress. API key comes
from `ZOTERO_API_KEY`.

### Key design points in the corpus→CSL mapping

#### Schema resilience (`.build_select_sql`)

This is the central concern and the function most likely to need edits. OpenAlex
parquet schemas vary across openalexPro versions and across record sources, so the
mapping never assumes a column exists. The function:

- Reads the live column set via `SELECT * FROM src LIMIT 0` (in `corpus_to_csljson`)
  and passes `cols` in. Every field expression is chosen with a `has(name)` guard.
- Falls back to a typed null (`CAST(NULL AS VARCHAR/INTEGER/BOOLEAN)`) for missing
  scalar columns, or an empty list `[]` for missing list columns (issns, authors,
  orcids, keywords). The downstream R code relies on these placeholders existing,
  so the `SELECT` always emits the *same column names* regardless of input schema.
- Handles **two venue layouts** that coexist in the wild: the legacy `host_venue`
  struct and the newer `primary_location.source` struct. When both are present it
  `COALESCE`s them (host_venue first); when only one is present it uses that. This
  applies to venue name, venue type, publisher, `issn_l`, and `issn`. If you touch
  venue handling, keep all five expressions consistent.
- Uses DuckDB struct/list navigation directly in SQL: dotted paths like
  `primary_location.source.display_name`, and `list_transform(authorships, x -> ...)`
  to pluck author display names and ORCIDs into parallel arrays.
- `url` is a `COALESCE` priority chain: `doi_url` → `open_access.oa_url` →
  `primary_location.landing_page_url` → `id`.
- ISBN is deliberately hard-coded to `CAST(NULL AS VARCHAR)` — the nested path is
  unreliable, so ISBN is effectively disabled at the SQL layer (see the comment).

**To add a mapped field you must touch two places**, and they share assumptions:
add the `has()`-guarded expression with an `AS <name>` alias in `.build_select_sql()`,
then read `rec$<name>` in `.map_record_to_csl()`. List-typed columns come back as
list-columns, so they are accessed as `rec$<name>[[1]]` (note the double bracket).

#### Row → CSL item (`.map_record_to_csl`)

Converts one SQL result row to a CSL item list. Notable behaviors:

- `%||%` is a custom coalesce defined here (not rlang's): it treats `NULL`,
  length-0, `NA`, **and empty string** all as missing. Used pervasively for scalars.
- Authors: names are split by `.split_name()` (handles `"Family, Given"` and
  space-separated, taking the last token as family). ORCIDs ride along in a parallel
  array, matched by index.
- `issued` date-parts: prefers `publication_date` (split on `-` into year/month/day),
  falling back to `year` alone.
- An aggregated `note` field encodes OA status and citation count
  (`OA:true; OA_status:gold; Citations:42`) since CSL has no native fields for these.
- Keywords (from `concepts`) are collapsed to a single `"; "`-joined string.
- ISBN is only emitted for `book`/`chapter`/`report` types — but since the SQL
  always nulls ISBN, this branch is currently dead unless the SQL is changed too.

#### CSL type inference (`.infer_csl_type`)

Maps OpenAlex `type`/venue-type strings to CSL types via regex (e.g.
`journal-article` → `article-journal`, `book-chapter` → `chapter`,
`posted-content`/`preprint` → `manuscript`). It then applies signal-based overrides:
presence of ISBN nudges toward `book`, ISSN toward `article-journal`, and a
container + volume/issue toward `article-journal`. Default when nothing matches is
`article-journal`.

#### Sanitization (`.sanitize_csl_item`)

Runs recursively over the assembled item before serialization: drops `NULL` and
scalar `NA`, normalizes character data to UTF-8 (`iconv`), strips control chars and
collapses whitespace, caps `abstract` at **700 chars**, and cleans author sublists
(removes `NA`/`"NA"` ORCIDs, blanks `NA` given/family). The 700-char abstract cap
here is separate from the 10000-char cap in the Pandoc stage (below).

#### DOI normalization (`.normalize_doi`)

Delegates to `openalexPro::extract_doi(..., normalize = TRUE, what = "doi")` to get
a bare DOI, with a regex strip of the resolver prefix as fallback if that call
errors. Do **not** reimplement DOI parsing here — a past bug (see `NEWS.md`) came
from a local regex that missed lowercase suffixes; the fix was to delegate.

#### Pandoc abstract guard (`.normalize_json_for_pandoc`)

Before bibtex/biblatex/formatted conversion, this re-serializes the JSON (for
consistent encoding) and, for directory/chunk conversion, drops any abstract longer
than **10000 chars** — long abstracts can stall pandoc/LaTeX. Single-file bibtex
conversion calls it with `drop_long_abstracts = FALSE`. The returned `$sanitized`
flag is surfaced in the verbose `[sanitized]` log marker.

## Tests

`tests/testthat/test-001-corpus_csl_pandoc.R` runs the full pipeline against
parquet fixtures in `tests/fixtures/corpus/` and compares output against golden
fixtures (`corpus_csl/`, `corpus_bibtex/`, `corpus_biblatex/`, `corpus_docs/`).

Important: exact-text comparison of Pandoc output is **Pandoc-version sensitive**,
so those assertions are guarded by `skip_on_ci()`. JSON-structure comparison (the
stage-1 output) is exact and always runs. Most tests `skip_if_not(rmarkdown::pandoc_available())`.
If you change the CSL mapping, the golden JSON fixtures in `tests/fixtures/corpus_csl/`
must be regenerated to match.

## Docs / vignettes

Vignettes are Quarto (`.qmd`, `VignetteBuilder: quarto`) in `vignettes/`. The
`vignettes/` dir is in `.Rbuildignore` (excluded from the tarball to avoid R CMD
check warnings). `pkgnet_report.qmd` is a generated package-network report.
