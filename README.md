[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20448988.svg)](https://doi.org/10.5281/zenodo.20448988)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)
[![License: GPL-2+](https://img.shields.io/badge/License-GPL%20%3E%3D%202-blue.svg)](https://www.gnu.org/licenses/gpl-2.0)
[![Codecov](https://codecov.io/gh/openalexPro/openalexConvert/graph/badge.svg)](https://app.codecov.io/gh/openalexPro/openalexConvert)

# openalexConvert

Convert an [OpenAlex](https://openalex.org) parquet corpus (produced by
[openalexPro](https://github.com/openalexPro/openalexPro)) into bibliography formats via
[Pandoc](https://pandoc.org): CSL JSON, BibTeX, BibLaTeX, Markdown, LaTeX, HTML, or PDF, and into
[Zotero](https://www.zotero.org).

## Installation

```r
install.packages(
  "openalexConvert",
  repos = c("https://openalexpro.r-universe.dev", "https://cloud.r-project.org")
)
```

Pandoc must be installed and on your `PATH` (or installed via `install.packages("rmarkdown")`
which bundles Pandoc on most platforms).

## Quick start

```r
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

## Zotero

With the Zotero desktop app (Zotero 10) running, select the target library or
collection in Zotero, then:

```r
# 3. Import the CSL JSON into Zotero; the OpenAlex ID goes into Extra
csljson_to_zotero("path/to/csljson")

# 4. After tagging in Zotero: read the tags back, by OpenAlex ID
zotero_tags("path/to/project")  # writes path/to/project/zotero_tags.parquet
```

## Documentation

Full documentation and vignettes: <https://openalexpro.github.io/openalexConvert/>

## Related packages

- [openalexPro](https://github.com/openalexPro/openalexPro) — API access and parquet output
- [openalexSnowball](https://github.com/openalexPro/openalexSnowball) — snowball citation search
