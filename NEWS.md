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
