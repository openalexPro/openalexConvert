# Convert a corpus to CSL JSON (chunked)

Maps an OpenAlex-like corpus (Arrow Dataset/Table or data.frame/tibble)
to CSL JSON items and writes them into chunked files. The function
creates the directory `output` (if not present) and writes files
`chunk_1.json`, `chunk_2.json`, ... inside that directory.

## Usage

``` r
corpus_to_csljson(
  project_dir,
  corpus = file.path(project_dir, "parquet"),
  output = file.path(project_dir, "csljson"),
  chunk_size = 10000,
  overwrite = FALSE,
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Optional path to project directory. If provided, used to set default
  values for `corpus` and `output` parameters. Can be omitted if
  `corpus` and `output` are specified explicitly.

- corpus:

  Path to parquet dataset, parquet Dataset/Table (e.g., from
  [`arrow::open_dataset()`](https://arrow.apache.org/docs/r/reference/open_dataset.html))
  or a data.frame/tibble (e.g., from
  [`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)).

- output:

  Path to a directory to create and populate with chunked CSL JSON files
  (`chunk_1.json`, `chunk_2.json`, ...).

- chunk_size:

  Rows processed per chunk via DuckDB. Default: 10000.

- overwrite:

  Overwrite `output` if it exists. Default: FALSE.

- verbose:

  Print progress messages. Default: TRUE.

## Value

Invisibly returns `normalizePath(output)`.

## Details

This converter targets the most common OpenAlex field layout and is
resilient to missing columns by falling back to `NULL`/empty values in
SQL. Mapping includes: title, year, DOI, container-title (venue),
volume/issue/pages, authors (with basic given/family split and ORCID
when present), URL/abstract, publisher and ISSN, language, keywords
(collapsed to a single string), and an aggregated `note` with OA status
and citation count. Records are processed in DuckDB-backed chunks for
low memory usage.
