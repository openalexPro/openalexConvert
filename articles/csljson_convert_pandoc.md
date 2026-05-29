# Converting CSL JSON via Pandoc

## Introduction

[`csljson_convert_pandoc()`](https://rkrug.github.io/openalexConvert/reference/csljson_convert_pandoc.md)
turns CSL JSON into a variety of bibliographic outputs using Pandoc’s
citeproc. It supports both single CSL JSON files and directories created
by
[`corpus_to_csljson()`](https://rkrug.github.io/openalexConvert/reference/corpus_to_csljson.md)
containing `chunk_*.json` files.

### Supported targets (`to`)

- Bibliography files: `"bibtex"`, `"biblatex"`
- Formatted documents: `"markdown"`, `"latex"`, `"docx"`, `"html"`,
  `"pdf"`

### Why Pandoc citeproc?

- Interoperability: Pandoc consumes CSL JSON natively and can emit many
  formats.
- Consistency: Formatting is controlled via CSL styles (e.g., APA),
  enabling reproducible references across outputs.

### Inputs and behavior

`csljson_convert_pandoc(csljson, output, to, ...)` adapts its behavior
to the nature of `csljson` and `to`:

#### Directory input (chunked CSL JSON)

- If `csljson` is a directory, it must contain `chunk_*.json` files.

- Bibliography outputs (`to = "bibtex" | "biblatex"`):

  - `output` must be a directory; one `.bib` file is written per chunk
    (`chunk_1.bib`, `chunk_2.bib`, …).

- Formatted documents
  (`to = "markdown" | "latex" | "docx" | "html" | "pdf"`):

  - `output` must be a directory; a single file is written inside with a
    canonical name: `references.md|tex|docx|html|pdf`.
  - All chunks are provided to citeproc via multiple `--bibliography=`
    flags; a small Markdown scaffold with `nocite: "@*"` ensures every
    entry is listed in the references section.

#### File input (single CSL JSON)

- Bibliography outputs (`to = "bibtex" | "biblatex"`):
  - `output` is the target `.bib` file; the extension is appended if
    missing.
- Formatted documents
  (`to = "markdown" | "latex" | "docx" | "html" | "pdf"`):
  - `output` is the target file; the extension is appended if missing.

### High‑level workflow

``` mermaid
flowchart TD
  A(["Input csljson<br/>(file &#124; chunk directory)"]) --> B{Target `to`}

  B -->|bibtex / biblatex| C{Is directory?}
  C -->|yes| D[Iterate chunk_*.json]
  D --> E["Normalize JSON per chunk<br/>(jsonlite; drop very long abstracts)"]
  E --> F["Pandoc convert → chunk_k.bib"]
  C -->|no file| G["Normalize single JSON<br/>(re‑serialize)"]
  G --> H["Pandoc convert → output.bib"]

  B -->|docx / markdown / latex / html / pdf| I{Is directory?}
  I -->|yes| J["Write refs.md (nocite: '@*')"]
  J --> K["Pandoc with multiple --bibliography=chunk_*.json"]
  K --> L["Write references.<ext> in output dir"]
  I -->|no file| M["Write refs.md (nocite: '@*')"]
  M --> N["Pandoc with --bibliography=input.json"]
  N --> O["Write output file (ext appended if missing)"]
```

### JSON normalization preflight

Normalization keeps Pandoc resilient to edge cases and standardizes the
on‑disk JSON. For directory→Bib\* it also drops pathological abstracts.

``` mermaid
flowchart TD
  X[Input JSON path] --> Y{Parse with jsonlite}
  Y -->|array of items| Z[For each item: if abstract length > 10000 → drop]
  Y -->|single object| Z2[If abstract length > 10000 → drop]
  Z --> W["Re‑serialize via jsonlite::toJSON(auto_unbox=TRUE)"]
  Z2 --> W
  W --> P[Temp JSON passed to Pandoc]

  %% Notes
  %% - Directory→Bib*: drop threshold active
  %% - File→Bib*: re‑serialize only (no drop)
  %% - Formatted outputs: pass JSONs directly
```

### Arguments

- `csljson`: Path to a CSL JSON file (array) or a directory created by
  [`corpus_to_csljson()`](https://rkrug.github.io/openalexConvert/reference/corpus_to_csljson.md).
- `output`: Directory (for directory input) or file path (for file
  input), as outlined above.
- `to`: One of `"biblatex"`, `"bibtex"`, `"docx"`, `"markdown"`,
  `"latex"`, `"html"`, `"pdf"`.
- `from` (default `"csljson"`): Source format hint for Pandoc when
  converting single files.
- `overwrite` (default `FALSE`): Overwrite existing outputs.
- `verbose` (default `TRUE`): Print progress and rendering messages.
- `references_csl` (optional): Path to a CSL style (e.g., APA `.csl`) to
  control formatted outputs.
- PDF options (apply when `to = "pdf"`): `pdf_engine` (default
  `"xelatex"`), `pdf_mainfont`, `pdf_sansfont`, `pdf_monofont`,
  `pdf_cjk_mainfont`, `pdf_cjk_options`.

### Implementation highlights

- Dependency checks: Requires the `rmarkdown` package and a working
  Pandoc installation
  ([`rmarkdown::pandoc_available()`](https://pkgs.rstudio.com/rmarkdown/reference/pandoc_available.html)).
- JSON normalization: When converting a single file, the function tries
  to read and rewrite the JSON with `jsonlite` to normalize whitespace
  before passing it to Pandoc.
- Chunk merging for formatted outputs: For directory inputs, all
  `chunk_*.json` are passed as individual `--bibliography=` flags so
  citeproc sees a single combined bibliography.
- Deterministic naming: Outputs for directory inputs always use the
  canonical name `references.<ext>` inside `output`.
- Markdown post‑processing: When `to = "markdown"`, fences created by
  Pandoc’s Divs are removed to yield a cleaner `.md`.

### Pandoc PDF options

``` mermaid
flowchart LR
  A[PDF options] --> B[pdf_engine]
  A --> C[Fonts]

  B --> E1["--pdf-engine=<engine>"]
  E1 --> E2["Always also add --pdf-engine=xelatex"]

  C --> M[mainfont]
  C --> S[sansfont]
  C --> O[monofont]
  C --> CJM[CJKmainfont]
  C --> CJO[CJKoptions]

  M --> VM["-V mainfont=…"]
  S --> VS["-V sansfont=…"]
  O --> VO["-V monofont=…"]
  CJM --> VCJM["-V CJKmainfont=…"]
  CJO --> VCJO["-V CJKoptions=…"]

  classDef node fill:#ffffff,stroke:#c7c7c7,color:#111,stroke-width:1px
  class A,B,C,M,S,O,CJM,CJO,E1,E2,VM,VS,VO,VCJM,VCJO node;
```

### Helper structure

``` mermaid
flowchart LR
  M["csljson_convert_pandoc()"] --> P[".check_pandoc_ready()"]
  M --> Q{"dir.exists(csljson)?"}

  Q -->|yes| D[Directory]
  Q -->|no| F[File]

  D --> T1{to in bibtex/biblatex?}
  T1 -->|yes| DB[".convert_dir_bib()"]
  T1 -->|no| DF[".render_dir_formatted()"]

  F --> T2{to in bibtex/biblatex?}
  T2 -->|yes| FB[".convert_file_bib()"]
  T2 -->|no| FF[".render_file_formatted()"]

  DB --> N1[".normalize_json_for_pandoc()"]
  FB --> N2[".normalize_json_for_pandoc()"]

  DF --> OP1[".build_pandoc_options()"]
  FF --> OP2[".build_pandoc_options()"]

  DF --> MD1[".write_refs_md()"]
  FF --> MD2[".write_refs_md()"]

  DB --> ED1[".ensure_dir()"]
  DF --> ED2[".ensure_dir()"]

  classDef node fill:#ffffff,stroke:#c7c7c7,color:#111,stroke-width:1px
  class M,P,Q,D,F,T1,DB,DF,T2,FB,FF,N1,N2,OP1,OP2,MD1,MD2,ED1,ED2 node;
```

### Error handling overview

``` mermaid
flowchart TD
  S[Start] --> A{rmarkdown installed?}
  A -->|no| E1[stop: require rmarkdown]
  A -->|yes| B{Pandoc available?}
  B -->|no| E2[stop: Pandoc not available]
  B -->|yes| C{`csljson` path exists?}
  C -->|no| E3[stop: input does not exist]
  C -->|yes| D{Is directory?}
  D -->|yes| D1{chunk_*.json present?}
  D1 -->|no| E4[stop: no chunks found]
  D1 -->|yes| D2{to in bibtex/biblatex?}
  D2 -->|yes| D3[Ensure output is directory]
  D2 -->|no| D4[Ensure output is directory]
  D3 --> OK1[Proceed]
  D4 --> OK1
  D -->|no file| F{to in bibtex/biblatex?}
  F -->|yes| F1[Resolve output .bib path]
  F -->|no| F2[Resolve output file + ext]
  F1 --> OK2[Proceed]
  F2 --> OK2
```

### Basic usage

Code

``` r

# Assume we already created chunked CSL JSON from a corpus
library(openalexConvert)

csl_dir <- tempfile("csljson_")
dir.create(csl_dir)
corpus_to_csljson(
  corpus = testthat::test_path("..", "fixtures", "corpus"),
  output = csl_dir,
  chunk_size = 10000,
  overwrite = TRUE,
  verbose = TRUE
)

# 1) Convert directory of chunks to BibTeX files
bib_dir <- tempfile("bib_")
paths_bib <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = bib_dir,
  to = "bibtex",
  overwrite = TRUE
)

# 2) Render a references document in Markdown (also: latex, docx, html, pdf)
doc_dir <- tempfile("docs_")
md_file <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = doc_dir,
  to = "markdown",
  overwrite = TRUE,
  references_csl = NULL # or a path to apa.csl
)
```

### Single‑file example

Code

``` r

# Load a single CSL JSON array and convert to BibLaTeX
blx_file <- tempfile(fileext = ".bib")
out_blx <- csljson_convert_pandoc(
  csljson = file.path(csl_dir, "chunk_1.json"),
  output = blx_file,
  to = "biblatex",
  overwrite = TRUE
)

# Create a LaTeX references file from a single chunk
tex_file <- csljson_convert_pandoc(
  csljson = file.path(csl_dir, "chunk_1.json"),
  output = tempfile(fileext = ".tex"),
  to = "latex",
  overwrite = TRUE
)
```

### BibTeX vs BibLaTeX comparison

While both targets encode bibliographic data, BibLaTeX is richer and
uses different field names in places. Below is a quick way to generate
both from the same CSL JSON and compare.

Conceptual differences to expect:

- Entry types: BibLaTeX may prefer `@article` with `date` over BibTeX’s
  `year`/`month` split; it also supports many more types.
- Field names: BibLaTeX uses `journaltitle` (vs `journal` in BibTeX),
  `date` (vs `year` + `month`), and handles `url`/`urldate` more
  consistently.
- Unicode: Modern BibLaTeX works well with Unicode (via `biber`), while
  BibTeX often requires escaping.

Code

``` r
# Produce both formats from the same chunked CSL JSON directory
out_bibtex <- tempfile("bibtex_")
out_biblatex <- tempfile("biblatex_")

paths_btx <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = out_bibtex,
  to = "bibtex",
  overwrite = TRUE
)

paths_blx <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = out_biblatex,
  to = "biblatex",
  overwrite = TRUE
)

# Inspect a corresponding pair (chunk_1)
btx <- readLines(file.path(out_bibtex, "chunk_1.bib"), warn = FALSE)
blx <- readLines(file.path(out_biblatex, "chunk_1.bib"), warn = FALSE)

utils::head(btx, 20)
utils::head(blx, 20)

# Optional: a simple diff to spot field name changes
setdiff(gsub("\\\s+", " ", blx), gsub("\\\s+", " ", btx))
```

### Styling with CSL

To control the appearance of formatted outputs, pass a CSL file via
`references_csl`:

Code

``` r

md_file <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = doc_dir,
  to = "markdown",
  references_csl = "/path/to/apa.csl",
  overwrite = TRUE
)
```

### PDF tips

- PDF creation depends on a LaTeX engine. The default is `xelatex` for
  Unicode support; change via `pdf_engine`.
- Font options (`pdf_mainfont`, `pdf_sansfont`, `pdf_monofont`) and CJK
  options (`pdf_cjk_mainfont`, `pdf_cjk_options`) can resolve missing
  glyphs in multilingual bibliographies.

### PDF arguments reference

These parameters are forwarded to Pandoc when `to = "pdf"`:

- `pdf_engine`: LaTeX engine; mapped to `--pdf-engine=<engine>`. Common
  values: `xelatex` (default), `lualatex`, `pdflatex`.
- `pdf_mainfont`: Sets Pandoc variable `mainfont` (`-V mainfont=...`).
- `pdf_sansfont`: Sets Pandoc variable `sansfont` (`-V sansfont=...`).
- `pdf_monofont`: Sets Pandoc variable `monofont` (`-V monofont=...`).
- `pdf_cjk_mainfont`: Sets Pandoc variable `CJKmainfont`
  (`-V CJKmainfont=...`).
- `pdf_cjk_options`: Sets Pandoc variable `CJKoptions`
  (`-V CJKoptions=...`).

Example with custom fonts and engine:

Code

``` r

pdf_file <- csljson_convert_pandoc(
  csljson = csl_dir,
  output = doc_dir,
  to = "pdf",
  overwrite = TRUE,
  pdf_engine = "xelatex",
  pdf_mainfont = "Source Serif Pro",
  pdf_sansfont = "Source Sans Pro",
  pdf_monofont = "Source Code Pro",
  pdf_cjk_mainfont = NULL, # e.g., "Noto Sans CJK SC"
  pdf_cjk_options = NULL # e.g., "BoldFont=Noto Sans CJK SC Bold"
)
```

### Determinism notes

- DOCX and PDF containers may include non‑deterministic metadata. For
  testing, compare content (e.g., convert both sides to plain text via
  Pandoc) rather than raw bytes.
- Markdown, LaTeX, BibTeX, and BibLaTeX are generally stable for
  byte‑wise comparison, provided your Pandoc version is fixed.

### Troubleshooting

- Ensure `rmarkdown` is installed and
  [`rmarkdown::pandoc_available()`](https://pkgs.rstudio.com/rmarkdown/reference/pandoc_available.html)
  is TRUE.
- If conversion fails on specific records, try normalizing the input
  JSON with `jsonlite` (the function does this for single‑file inputs).
- For directory inputs, verify `chunk_*.json` exist in the CSL folder.
