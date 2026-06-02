# openalexConvert

Convert an [OpenAlex](https://openalex.org) parquet corpus (produced by
[openalexPro](https://github.com/openalexPro/openalexPro)) into
bibliography formats via [Pandoc](https://pandoc.org): CSL JSON, BibTeX,
BibLaTeX, Markdown, LaTeX, HTML, or PDF.

## Installation

``` r

install.packages(
  "openalexConvert",
  repos = c("https://openalexpro.r-universe.dev", "https://cloud.r-project.org")
)
```

Pandoc must be installed and on your `PATH` (or installed via
`install.packages("rmarkdown")` which bundles Pandoc on most platforms).

## Quick start

``` r

library(openalexConvert)

# 1. Convert an openalexPro parquet corpus to CSL JSON
corpus_to_csljson(
  corpus = "path/to/parquet",
  output = "path/to/csljson"
)

# 2. Convert CSL JSON directory to BibTeX
csljson_convert_pandoc(
  input  = "path/to/csljson",
  output = "path/to/bibliography.bib",
  to     = "bibtex"
)
```

## Documentation

Full documentation and vignettes:
<https://openalexpro.github.io/openalexConvert/>

## Related packages

- [openalexPro](https://github.com/openalexPro/openalexPro) — API access
  and parquet output
- [openalexSnowball](https://github.com/openalexPro/openalexSnowball) —
  snowball citation search
