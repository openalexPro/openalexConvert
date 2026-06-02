# Changelog

## openalexConvert 0.0.3

### Bug fixes

- [`corpus_export_via_pandoc()`](https://openalexpro.github.io/openalexConvert/reference/corpus_export_via_pandoc.md):
  now produces a single output file (e.g. `corpus.bib`) as documented.
  Previously it passed the chunked CSL JSON directory to
  [`csljson_convert_pandoc()`](https://openalexpro.github.io/openalexConvert/reference/csljson_convert_pandoc.md),
  which created a *directory* of per-chunk files at the `output` path,
  and it returned the wrong path when an extension had to be appended.
- [`csljson_convert_pandoc()`](https://openalexpro.github.io/openalexConvert/reference/csljson_convert_pandoc.md):
  the `pdf_engine` parameter is now respected. Previously
  `--pdf-engine=xelatex` was unconditionally appended, overriding any
  user-specified engine (e.g. `"lualatex"` or `"pdflatex"`).
- DOI extraction now delegates to
  [`openalexPro::extract_doi()`](https://openalexpro.github.io/openalexPro/reference/extract_doi.html),
  which fixes a regex that missed lowercase characters in DOI suffixes
  (e.g. `10.1234/abc-def`).

### Improvements

- `openalexPro` declared as a formal dependency in `DESCRIPTION`
  (`Imports`).
- `rmarkdown` moved from `Suggests` to `Imports` (it is used in exported
  functions).
- `Additional_repositories` added to `DESCRIPTION` so CI and users can
  resolve `openalexPro` from r-universe automatically.
- CI aligned with the rest of the openalexPro ecosystem: standard
  `R-CMD-check.yaml` (macOS, Windows, Ubuntu × devel/release/oldrel-1)
  and `test-coverage.yaml` added.
- Test coverage raised to ~86%, with new tests for
  [`corpus_export_via_pandoc()`](https://openalexpro.github.io/openalexConvert/reference/corpus_export_via_pandoc.md),
  Pandoc rendering paths, and
  [`csljson_to_zotero_upload()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero_upload.md).
- Leftover `_problems/` test artefacts from a previous failed run
  removed.
