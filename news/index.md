# Changelog

## openalexConvert (development version)

### Bug fixes

- [`csljson_convert_pandoc()`](https://rkrug.github.io/openalexConvert/reference/csljson_convert_pandoc.md):
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
- Leftover `_problems/` test artefacts from a previous failed run
  removed.
