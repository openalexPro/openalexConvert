# Read Zotero tags by OpenAlex ID

Reads the tags of all items in the Zotero library **currently selected
in Zotero** whose Extra holds an OpenAlex ID (any of the forms listed in
[`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md))
and writes them to a parquet file next to the corpus. Tag works in
Zotero, then join the table with the corpus on `openalex_id`.

The whole library is read, not only the selected collection. Rows of
other libraries already in `output` are kept; rows of this library are
replaced, so the file always holds the library's current tags. Items
without an OpenAlex ID in Extra are not included.

Needs the running Zotero desktop app (Zotero 10 or later, for the local
API); reading needs no API key. It runs the same search as
[`csljson_to_zotero()`](https://openalexpro.github.io/openalexConvert/reference/csljson_to_zotero.md)
(see its "Speed" section): a few seconds for a library of 5000 works.

## Usage

``` r
zotero_tags(
  project_dir,
  output = file.path(project_dir, "zotero_tags.parquet"),
  url = "http://127.0.0.1:23119"
)
```

## Arguments

- project_dir:

  Path to the project directory. Used for the default of `output`.

- output:

  Path of the parquet file. Default
  `file.path(project_dir, "zotero_tags.parquet")`.

- url:

  Base URL of the local Zotero server. Default
  `"http://127.0.0.1:23119"`.

## Value

Invisibly, a data.frame with one row per item and tag (the rows of this
library), as written to `output`:

- openalex_id:

  OpenAlex work ID, e.g. `"W2112574986"`.

- tag:

  The tag.

- type:

  `0` for a tag added by hand, `1` for one added automatically (e.g. by
  an import translator).

- zotero_library:

  Group ID, or `0` for the personal library.

- zotero_key:

  Zotero item key.

A work in the library twice gives rows for each Zotero item.

## Examples

``` r
if (FALSE) { # \dontrun{
# In Zotero, select the library first.
tags <- zotero_tags("my_project")
# works tagged "include" in Zotero
unique(subset(tags, tag == "include")$openalex_id)
} # }
```
