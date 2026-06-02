# Convert CSL JSON (file or directory) via Pandoc

Converts CSL JSON with Pandoc into one of: BibTeX, BibLaTeX, Docx,
Markdown, LaTeX, or PDF. Behavior depends on `to`:

- `bibtex`/`biblatex`: creates bibliography files. For a directory of
  chunks, writes `chunk_*.bib` into the directory given by `output`. For
  a single file, writes the specified `output` (appends `.bib` if
  missing).

- `docx`/`markdown`/`latex`/`pdf`: renders a formatted references
  document using citeproc. For a directory of chunks, writes
  `references.<ext>` inside `output`. For a single file, writes to
  `output` (appends extension if missing).

## Usage

``` r
csljson_convert_pandoc(
  csljson,
  output,
  to = c("biblatex", "bibtex", "docx", "markdown", "latex", "html", "pdf"),
  from = "csljson",
  overwrite = FALSE,
  verbose = TRUE,
  references_csl = NULL,
  pdf_engine = "xelatex",
  pdf_mainfont = NULL,
  pdf_sansfont = NULL,
  pdf_monofont = NULL,
  pdf_cjk_mainfont = NULL,
  pdf_cjk_options = NULL
)
```

## Arguments

- csljson:

  Path to a CSL JSON file (array) or a directory created by
  [`corpus_to_csljson()`](https://openalexpro.github.io/openalexConvert/reference/corpus_to_csljson.md)
  containing `chunk_*.json` files.

- output:

  Output path. For `bib*` with a file input, this is the target `.bib`
  file (extension added if missing). For `bib*` with a directory input,
  this is the output directory. For formatted references (`docx`,
  `markdown`, `latex`, `pdf`), this is the output file (file input) or
  the output directory (dir input; file will be `references.<ext>`
  within).

- to:

  One of `"biblatex"`, `"bibtex"`, `"docx"`, `"markdown"`, `"latex"`,
  `"html"`, or `"pdf"`.

- from:

  Source format; defaults to "csljson".

- overwrite:

  Logical; overwrite existing output file(s). Defaults to FALSE.

- verbose:

  Print progress messages.

- references_csl:

  Optional path to a CSL style file (e.g., apa.csl). If NULL, Pandoc's
  default style is used.

- pdf_engine:

  LaTeX engine used when `to = "pdf"`. Common values are `"xelatex"`
  (default, good Unicode support), `"lualatex"`, or `"pdflatex"`. Passed
  to Pandoc as `--pdf-engine`.

- pdf_mainfont:

  Main text font name for PDF output (used with XeLaTeX/LuaLaTeX). Sets
  Pandoc variable `mainfont` (e.g., `-V mainfont=Source Serif Pro`).

- pdf_sansfont:

  Sans‑serif font name for PDF output. Sets Pandoc variable `sansfont`.

- pdf_monofont:

  Monospace font name for PDF output. Sets Pandoc variable `monofont`.

- pdf_cjk_mainfont:

  Main CJK font name for PDF output. Sets Pandoc variable `CJKmainfont`
  for better East‑Asian typography.

- pdf_cjk_options:

  Additional CJK options passed via Pandoc variable `CJKoptions` (e.g.,
  feature flags accepted by `xeCJK`).

## Value

Invisibly returns the created file path(s).

## Details

Requires Pandoc to be available. In RStudio, a bundled Pandoc is usually
available; otherwise install Pandoc and ensure it is on PATH.

When rendering `to = "pdf"`, this function maps the supplied PDF options
to Pandoc command line flags and variables as follows:

- `pdf_engine` → `--pdf-engine=<engine>`

- `pdf_mainfont`, `pdf_sansfont`, `pdf_monofont` → `-V mainfont=...`,
  `-V sansfont=...`, `-V monofont=...`

- `pdf_cjk_mainfont`, `pdf_cjk_options` → `-V CJKmainfont=...`,
  `-V CJKoptions=...`

Use these to ensure Unicode coverage and consistent typography,
especially for multilingual bibliographies.
