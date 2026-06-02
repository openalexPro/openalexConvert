# One-shot export via CSL JSON + Pandoc

Convenience wrapper that maps a corpus to CSL JSON, then converts it to
the desired output format via Pandoc.

## Usage

``` r
corpus_export_via_pandoc(
  corpus,
  output,
  to = c("bibtex", "biblatex"),
  csl_tmp = NULL,
  ...
)
```

## Arguments

- corpus:

  Arrow Dataset/Table or data.frame/tibble of works.

- output:

  Path to the final file (e.g., \`corpus.bib\`).

- to:

  Target format passed to Pandoc (e.g., \`"bibtex"\`, \`"biblatex"\`).

- csl_tmp:

  Optional path for a temporary CSL JSON directory. If \`NULL\`, a
  temporary directory is used and removed afterwards.

- ...:

  Additional arguments passed to \`corpus_to_csljson()\` (e.g.,
  \`chunk_size\`).

## Value

Invisibly returns the normalized path to the created file.
