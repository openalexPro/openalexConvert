# One-shot export of a corpus to Zotero

Convenience wrapper: maps a corpus to CSL JSON with
[`corpus_to_csljson()`](https://openalexpro.github.io/openalexConvert/reference/corpus_to_csljson.md)
(in a temporary directory, removed afterwards) and imports it into the
library selected in Zotero with
[`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md).
See there for re-exports (`existing`), tags, collections and the import
speed.

## Usage

``` r
corpus_to_zotero(
  project_dir,
  corpus = file.path(project_dir, "parquet"),
  existing = c("skip", "update", "overwrite"),
  tags,
  collection,
  chunk_size = 1000,
  ...
)
```

## Arguments

- project_dir:

  Optional path to the project directory, used for the default of
  `corpus`.

- corpus:

  Path to parquet dataset, Arrow Dataset/Table or data.frame/tibble of
  works. Default `file.path(project_dir, "parquet")`.

- existing:

  `"skip"` (default), `"update"` or `"overwrite"`: what to do with works
  already in the Zotero library. See
  [`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md).

- tags:

  Tags to write, by OpenAlex ID (see "Tags" in
  [`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md)):
  a data.frame, a parquet path, or `NULL` for none. Default:
  `<project_dir>/zotero_tags.parquet` (written by
  [`zotero_tags()`](https://openalexpro.github.io/openalexConvert/reference/zotero_tags.md))
  if it exists, else `NULL`.

- collection:

  Path of the Zotero collection to export into. Default:
  `c(<name of project_dir>, <name of corpus>)`, leaving out what has no
  name (a corpus given as a data.frame); `.parquet` is dropped from the
  corpus name. `NULL` puts the works only into what is selected in
  Zotero.

- chunk_size:

  Works per file sent to Zotero. Default `1000`, which gives progress
  per 1000 works and stays well within `timeout`.

- ...:

  Further arguments to
  [`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md)
  (`method`, `url`, `api_key`, `timeout`).

## Value

Invisibly, the data.frame returned by
[`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md),
one row per chunk.

## Details

By default the works go into their own nested collection, named after
the project directory and the corpus (`<project>` \> `<corpus>`), so an
accidental export is easy to find and delete. Select the library itself
in Zotero (not a collection) before exporting.

## Examples

``` r
if (FALSE) { # \dontrun{
# In Zotero, select the target library or collection first.
res <- corpus_to_zotero("my_project")
subset(res, !ok)
} # }
```
