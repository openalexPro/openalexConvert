# Upload CSL JSON batch files to a Zotero group library (with progress bar)

Upload one or more CSL-JSON files to a Zotero **group** library using
the Zotero Web API. Each file is assumed to contain an array of item
objects suitable for POSTing to `/groups/{group_id}/items`.

Progress is reported via the progressr package, which integrates with
future / future.apply progress handlers.

## Usage

``` r
csljson_to_zotero_upload(
  files,
  group_id,
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  pause = 0.5
)
```

## Arguments

- files:

  Character vector. Paths to CSL-JSON files. If a single element points
  to an existing directory, all `*.json` files in that directory
  (non-recursive) are used.

- group_id:

  Character or numeric. Zotero **group** ID.

- api_key:

  Character. Zotero API key with write access to the group. Defaults to
  `Sys.getenv("ZOTERO_API_KEY")`.

- pause:

  Numeric scalar. Number of seconds to wait between requests (to avoid
  rate limiting). Default is `0.5`.

## Value

A data.frame with one row per file and columns:

- file:

  Path to the CSL-JSON file.

- status_code:

  HTTP status code returned by the Zotero API.

- ok:

  Logical; `TRUE` if `status_code` is in 200–299.

- message:

  Character; short message or error text (possibly truncated).

Invisibly returns this data.frame.

## Examples

``` r
if (FALSE) { # \dontrun{
library(progressr)
handlers(global = TRUE)
handlers("cli")  # or "progress", "txtprogressbar", etc.

res <- csljson_to_zotero_upload(
  files    = "csljson_batches",  # directory with items_0001.json, ...
  group_id = "123456",
  api_key  = Sys.getenv("ZOTERO_API_KEY")
)

subset(res, !ok)  # inspect failures
} # }
```
