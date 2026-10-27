# Import CSL JSON files into Zotero

Import one or more CSL JSON files (e.g. the chunks written by
[`corpus_to_csljson()`](https://openalexpro.github.io/openalexConvert/reference/corpus_to_csljson.md))
into Zotero.

- `method = "local"` sends the items to a running Zotero desktop app via
  its local connector endpoint (`/connector/import`, the endpoint the
  browser connector uses). Zotero's own CSL JSON importer does the
  mapping. Items go into the library or collection **currently selected
  in Zotero**; select a group library there to import into the group,
  and Zotero sync uploads them.

- `method = "web"` (headless upload via the Zotero Web API) is not
  implemented yet and raises an error.

Zotero imports the CSL `note` into **Extra**; for files written by
[`corpus_to_csljson()`](https://openalexpro.github.io/openalexConvert/reference/corpus_to_csljson.md)
its first line is the item's `OpenAlex: W...`.

## Usage

``` r
csljson_to_zotero(
  files,
  method = c("local", "web"),
  existing = c("skip", "update", "overwrite"),
  tags = NULL,
  collection = NULL,
  url = "http://127.0.0.1:23119",
  api_key = Sys.getenv("ZOTERO_LOCAL_API_KEY"),
  timeout = 3600
)
```

## Arguments

- files:

  Character vector. Paths to CSL JSON files. If a single element points
  to an existing directory, all `*.json` files in that directory
  (non-recursive) are used.

- method:

  `"local"` (default) or `"web"`. See Description.

- existing:

  `"skip"` (default), `"update"` or `"overwrite"`: what to do with items
  whose OpenAlex ID is already in the selected Zotero library. See
  "Items already in Zotero".

- tags:

  `NULL` (default: no tags written), or a data.frame or path to a
  parquet file with columns `openalex_id`, `tag` and optionally `type`
  (`0` manual, `1` automatic), such as the one written by
  [`zotero_tags()`](https://openalexpro.github.io/openalexConvert/reference/zotero_tags.md).
  See "Tags".

- collection:

  `NULL` (default: only the target selected in Zotero), or the path of a
  collection to put the works in, e.g. `c("my_project", "corpus_a")`.
  See "Collection".

- url:

  Base URL of the local Zotero server. Default
  `"http://127.0.0.1:23119"`.

- api_key:

  Key for Zotero's local API, only needed for `existing = "update"` or
  `"overwrite"`, `tags` or `collection`. Defaults to
  `Sys.getenv("ZOTERO_LOCAL_API_KEY")`; if empty, Zotero is asked for
  one.

- timeout:

  Seconds to wait for Zotero to import one file. Default `3600`; a
  10000-item chunk can take 10 to 30 minutes (see "Speed").

## Value

Invisibly, a data.frame with one row per file and columns:

- file:

  Path to the CSL JSON file.

- status_code:

  HTTP status code of the last import request (`201` on success, `NA` if
  nothing had to be imported).

- ok:

  Logical; `TRUE` if every step for the file succeeded.

- n_items:

  Number of new items imported.

- n_skipped:

  Number of items skipped because they already exist.

- n_updated:

  Number of existing Zotero items updated or overwritten.

- n_tagged:

  Number of items whose tags were written from `tags`.

- message:

  Character; error text if something failed.

## Items already in Zotero

Before importing, the selected **library** (all of it, not only the
selected collection) is searched for items whose Extra holds an OpenAlex
ID, in any of the forms in use: `OpenAlex: W...` (written by this
package), `OpenAlex: https://openalex.org/W...` (Zotero's OpenAlex
translators), `openalex.work_id: W...` and `OpenAlex Work ID: W...` (two
Zotero plugins). Items whose OpenAlex ID is not found there (or that
have none) are imported. Items already there are handled by `existing`:

- `"skip"` (default): left untouched and not imported.

- `"update"`: the existing Zotero item gets the new metadata; fields the
  new metadata does not have keep their old values.

- `"overwrite"`: all fields of the existing Zotero item are replaced by
  the new metadata; fields it does not have are emptied.

With `"update"` and `"overwrite"` the existing item keeps its item key,
child notes and attachments, tags, collections and related items.
Technically, the items are imported with Zotero's CSL JSON importer,
their fields are copied onto the existing items, and the imported copies
are deleted again.

## Tags

CSL JSON has no tags, so by default items arrive without tags, and
existing items keep theirs. With `tags` (e.g. the `zotero_tags.parquet`
written by
[`zotero_tags()`](https://openalexpro.github.io/openalexConvert/reference/zotero_tags.md)),
tags are written by OpenAlex ID, following `existing`:

- new items get the tags of their OpenAlex ID;

- `"skip"`: existing items are left untouched, tags included;

- `"update"`: tags missing on the existing item are added, its own are
  kept;

- `"overwrite"`: the existing item's tags are replaced by those in
  `tags`, and removed if `tags` has none for its OpenAlex ID.

Rows of several libraries are merged; a tag keeps its type (manual or
automatic).

## Collection

With `collection`, e.g. `c("my_project", "corpus_a")`, the works are
also put into that collection, nested from the top level of the selected
library (`my_project` \> `corpus_a`). Missing collections are created,
existing ones of the same name reused, so a re-export goes into the same
collection. Works already in the library join the collection too, with
every value of `existing`: collections are independent of the item, and
one work can be in several. Other collections of an item are kept.

New items also land in whatever is selected in Zotero, so select the
library itself (not a collection) to have them only in `collection`.
Deleting the collection in Zotero with its items removes an accidental
export again; items that were already in the library before stay in
their other collections.

## Write access

`"update"`, `"overwrite"`, `tags` and `collection` write through
Zotero's local API, which needs Zotero 10 or later and a key. If
`api_key` is empty, Zotero shows a dialog asking to allow access for
"openalexConvert": choose **Always Allow** (a key allowed once is only
good for a single write). The key is kept for the rest of the R session.

Progress is reported via the progressr package.

## Speed

Zotero gets slower as the library grows. Measured with Zotero 10.0.6 on
a Mac, importing 5000 works in files of 1000 into a library starting at
about 440 items:

|      |                         |       |         |
|------|-------------------------|-------|---------|
| file | items in library before | time  | works/s |
| 1    | 440                     | 57 s  | 17.5    |
| 2    | 1440                    | 89 s  | 11.2    |
| 3    | 2440                    | 121 s | 8.3     |
| 4    | 3440                    | 145 s | 6.9     |
| 5    | 4440                    | 163 s | 6.1     |

Zotero's memory use grew to 3.4 GB during that run. For 100000 works,
plan for several hours to more than a day, and consider restarting
Zotero every few files.

The search for items already in the library (run once per call, for
every value of `existing`) took 0.2 s for 369 IDs and 6.6 s for 5369; it
grows faster than the library, so expect tens of minutes for 100000.
Re-running all 5000 works with `existing = "skip"` took 4.7 s, mostly
that search.
[`corpus_to_csljson()`](https://openalexpro.github.io/openalexConvert/reference/corpus_to_csljson.md)
itself takes about 1 ms per work.

## Examples

``` r
if (FALSE) { # \dontrun{
# In Zotero, select the target library or collection first.
res <- csljson_to_zotero("csljson")  # directory with chunk_1.json, ...
subset(res, !ok)

# Re-export after the corpus was updated: refresh what is already there
csljson_to_zotero("csljson", existing = "update")
} # }
```
