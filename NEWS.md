# openalexConvert 0.1.0

## Zotero import rewritten

`csljson_to_zotero_upload()` is removed. It POSTed CSL JSON to the Zotero Web
API, which only accepts Zotero item JSON and at most 50 items per request, so
real uploads could not succeed; its tests only exercised mocked responses.

New `csljson_to_zotero(files, method = c("local", "web"))`:

- `method = "local"` imports CSL JSON files (e.g. the chunks from
  `corpus_to_csljson()`) into the running Zotero desktop app via its local
  connector endpoint. Zotero's own CSL JSON importer does the mapping, and
  items go into the library or collection selected in Zotero; select a group
  library to import into the group. Verified against Zotero 10.0.6.
- Each item's OpenAlex ID ends up in Zotero's Extra field as `OpenAlex: W...`
  (see below).
- Re-exports: `existing = c("skip", "update", "overwrite")` decides what
  happens to items whose OpenAlex ID is already in the selected Zotero library.
  `"skip"` (default) leaves them alone; `"update"` writes the new metadata but
  keeps fields it lacks; `"overwrite"` replaces all fields and empties those it
  lacks. Both keep the Zotero item key, notes, attachments, tags and
  collections. They need Zotero 10's local API and a one-time "Always Allow"
  in Zotero.
- Existing items are recognised whichever form their Extra uses for the ID:
  `OpenAlex: W...` (written by this package), `OpenAlex: https://openalex.org/W...`
  (Zotero's OpenAlex translators), `openalex.work_id: W...` (zotero-openalex
  plugin) or `OpenAlex Work ID: W...` (open-alex-work-id plugin).
- `corpus_to_zotero(project_dir)` does both steps in one call: corpus to
  temporary CSL JSON (1000 works per file) to Zotero, into the collection
  `<project>` > `<corpus>`.
- Collections: `csljson_to_zotero(collection = c("project", "corpus"))` puts
  the works into a nested collection, created if missing and reused on
  re-export. Works already in the library join it too, whatever `existing`
  says. `corpus_to_zotero()` does this by default, naming the collections
  after the project directory and the corpus, so an accidental export is easy
  to find and delete.
- Tags: `csljson_to_zotero(tags = )` and `corpus_to_zotero()` write tags by
  OpenAlex ID (e.g. from `zotero_tags.parquet`, which `corpus_to_zotero()`
  picks up from the project directory). New items get their tags; existing
  items follow `existing`: `"skip"` leaves them alone, `"update"` adds
  missing tags, `"overwrite"` replaces them. New result column `n_tagged`.
- `method = "web"` (headless upload via the Zotero Web API) is not implemented
  yet and raises an error.
- The help page's "Speed" section gives measured import times: Zotero slows
  as the library grows (17.5 works/s at 440 items, 6.1 works/s at 4440), so
  100000 works take hours.

## OpenAlex ID in the CSL `note`

`corpus_to_csljson()` now writes `note` as lines, the first being
`OpenAlex: W...` (followed by the existing `OA:...; OA_status:...; Citations:...`
line). Zotero imports `note` into Extra, so the ID is kept however the CSL JSON
reaches Zotero, including File → Import. The CSL test fixtures were regenerated;
only `note` changed. BibTeX/BibLaTeX output is unchanged (pandoc does not write
`note`).

## Zotero tags back into the project

New `zotero_tags(project_dir)` reads the tags of every item in the Zotero
library selected in Zotero that has an OpenAlex ID in Extra (any of the four
forms) and writes them to `zotero_tags.parquet` in the project directory: one
row per work and tag, with the tag type (manual/automatic), the library (group
ID, `0` = personal library) and the Zotero item key. Join it with the corpus on
`openalex_id`. Re-running replaces that library's rows and keeps those of other
libraries. Reading needs no API key.

## DuckDB lambda syntax

`corpus_to_csljson()` failed with current DuckDB ("Deprecated lambda arrow
(->) detected"). It now uses the `lambda x: ...` syntax.

# openalexConvert 0.0.5

## Tests no longer compare pandoc's exact output

Every r-universe check failed — Linux, macOS and Windows, all R versions —
in `test-001-corpus_csl_pandoc.R`:

```
actual (r-universe):  year = {0000}
expected (fixture):   year = {0000},
                      doi = {10.1163/9789004190351_002}
```

r-universe builds with **pandoc 3.9**, which omits `doi = {...}` for these
entry types; the fixtures had been regenerated in 0.0.4 on a machine with
**pandoc 3.12**, which writes it. Same input, same code, different pandoc.

Those five comparisons were guarded by `skip_on_ci()`, which GitHub Actions
honours — so CI stayed green — but r-universe does not set `CI`, so they ran
there.

Byte-comparing pandoc's output tests pandoc, not this package. The tests now
compare what `csljson_convert_pandoc()` is actually responsible for: that
every record in comes out. BibTeX and BibLaTeX compare citation keys, LaTeX
compares the OpenAlex ids carried in `\bibitem`, and the markdown test keeps
its structural assertions (markdown renders citations as author-year text, so
no ids survive to match on).

The `skip_on_ci()` guards are gone with them, so these five now run on every
platform instead of being skipped on CI.

# openalexConvert 0.0.4

## Require openalexPro (>= 0.11.0)

`.normalize_doi()` delegates to `openalexPro::extract_doi(normalize = TRUE)`
(`R/corpus_to_csljson.R:430`), and before openalexPro 0.11.0 that function
silently truncated DOIs containing `<`, `>`, `[` or `]` -- returning a
shorter string that still looked like a valid DOI, with no warning and no
`NA`. Roughly 0.38% of real DOIs are affected (SICI-style ones, common in
older journal content).

The dependency carried no version floor, so installing against an older
openalexPro produced quietly corrupted DOIs in the CSL-JSON output.

## Fixtures regenerated: they encoded the truncation bug

Once the floor was in place the suite failed, because every comparison
fixture had been recorded while `extract_doi()` was still truncating. The
fixtures expected the *wrong* answer:

```
generated: "10.1659/0276-4741(2005)025[0206:pfbcs]2.0.co;2"   <- correct
fixture:   "10.1659/0276-4741(2005)025"                       <- truncated
```

The BibTeX and BibLaTeX fixtures were stale in a second way: entries whose
DOI had been lost now carry a `doi = {...}` field they previously lacked.

Every difference was verified to be DOI-related before regenerating -- 6
differing CSL fields and 187 differing `.bib` lines, all of them a DOI value
or a `doi =` line (plus the trailing comma that appears on the line above a
newly added field). Nothing else moved.

`data-raw/regenerate_fixtures.R` now does this reproducibly, and refuses to
run outside a UTF-8 locale: in a C locale R renders non-ASCII author names as
literal `<U+00F3>` escapes and pandoc writes
`Bay\textless U+00F3\textgreater n` into the `.bib` files, which is exactly
how a broken fixture gets committed and then becomes the expectation.

The suite now passes: 119 pass / 0 fail, from 105 pass / 14 fail.

# openalexConvert 0.0.3

## Bug fixes

- `corpus_export_via_pandoc()`: now produces a single output file (e.g.
  `corpus.bib`) as documented. Previously it passed the chunked CSL JSON
  directory to `csljson_convert_pandoc()`, which created a *directory* of
  per-chunk files at the `output` path, and it returned the wrong path when an
  extension had to be appended.
- `csljson_convert_pandoc()`: the `pdf_engine` parameter is now respected. Previously
  `--pdf-engine=xelatex` was unconditionally appended, overriding any user-specified
  engine (e.g. `"lualatex"` or `"pdflatex"`).
- DOI extraction now delegates to `openalexPro::extract_doi()`, which fixes a regex
  that missed lowercase characters in DOI suffixes (e.g. `10.1234/abc-def`).

## Improvements

- `openalexPro` declared as a formal dependency in `DESCRIPTION` (`Imports`).
- `rmarkdown` moved from `Suggests` to `Imports` (it is used in exported functions).
- `Additional_repositories` added to `DESCRIPTION` so CI and users can resolve
  `openalexPro` from r-universe automatically.
- CI aligned with the rest of the openalexPro ecosystem: standard `R-CMD-check.yaml`
  (macOS, Windows, Ubuntu × devel/release/oldrel-1) and `test-coverage.yaml` added.
- Test coverage raised to ~86%, with new tests for `corpus_export_via_pandoc()`,
  Pandoc rendering paths, and `csljson_to_zotero_upload()`.
- Leftover `_problems/` test artefacts from a previous failed run removed.
