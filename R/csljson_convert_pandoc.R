#' Convert CSL JSON (file or directory) via Pandoc
#'
#' Converts CSL JSON with Pandoc into one of: BibTeX, BibLaTeX, Docx, Markdown,
#' LaTeX, or PDF. Behavior depends on `to`:
#' - `bibtex`/`biblatex`: creates bibliography files. For a directory of chunks,
#'   writes `chunk_*.bib` into the directory given by `output`. For a single
#'   file, writes the specified `output` (appends `.bib` if missing).
#' - `docx`/`markdown`/`latex`/`pdf`: renders a formatted references document
#'   using citeproc. For a directory of chunks, writes `references.<ext>` inside
#'   `output`. For a single file, writes to `output` (appends extension if
#'   missing).
#'
#' @param csljson Path to a CSL JSON file (array) or a directory created by
#'   `corpus_to_csljson()` containing `chunk_*.json` files.
#' @param output Output path. For `bib*` with a file input, this is the target
#'   `.bib` file (extension added if missing). For `bib*` with a directory
#'   input, this is the output directory. For formatted references (`docx`,
#'   `markdown`, `latex`, `pdf`), this is the output file (file input) or the
#'   output directory (dir input; file will be `references.<ext>` within).
#' @param to One of `"biblatex"`, `"bibtex"`, `"docx"`, `"markdown"`,
#'   `"latex"`, `"html"`, or `"pdf"`.
#' @param from Source format; defaults to "csljson".
#' @param overwrite Logical; overwrite existing output file(s). Defaults to
#'   FALSE.
#' @param verbose Print progress messages.
#' @param references_csl Optional path to a CSL style file (e.g., apa.csl). If
#'   NULL, Pandoc's default style is used.
#' @param pdf_engine LaTeX engine used when `to = "pdf"`. Common values are
#'   `"xelatex"` (default, good Unicode support), `"lualatex"`, or
#'   `"pdflatex"`. Passed to Pandoc as `--pdf-engine`.
#' @param pdf_mainfont Main text font name for PDF output (used with
#'   XeLaTeX/LuaLaTeX). Sets Pandoc variable `mainfont` (e.g.,
#'   `-V mainfont=Source Serif Pro`).
#' @param pdf_sansfont Sans‑serif font name for PDF output. Sets Pandoc
#'   variable `sansfont`.
#' @param pdf_monofont Monospace font name for PDF output. Sets Pandoc
#'   variable `monofont`.
#' @param pdf_cjk_mainfont Main CJK font name for PDF output. Sets Pandoc
#'   variable `CJKmainfont` for better East‑Asian typography.
#' @param pdf_cjk_options Additional CJK options passed via Pandoc variable
#'   `CJKoptions` (e.g., feature flags accepted by `xeCJK`).
#'
#' @return Invisibly returns the created file path(s).
#'
#' @details Requires Pandoc to be available. In RStudio, a bundled Pandoc is
#' usually available; otherwise install Pandoc and ensure it is on PATH.
#'
#' When rendering `to = "pdf"`, this function maps the supplied PDF options to
#' Pandoc command line flags and variables as follows:
#' - `pdf_engine` → `--pdf-engine=<engine>`
#' - `pdf_mainfont`, `pdf_sansfont`, `pdf_monofont` → `-V mainfont=...`,
#'   `-V sansfont=...`, `-V monofont=...`
#' - `pdf_cjk_mainfont`, `pdf_cjk_options` → `-V CJKmainfont=...`,
#'   `-V CJKoptions=...`
#'
#' Use these to ensure Unicode coverage and consistent typography, especially
#' for multilingual bibliographies.
#'
#' @md
#'
#' @export
csljson_convert_pandoc <- function(
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
) {
  to <- match.arg(to)
  .check_pandoc_ready()
  if (!file.exists(csljson)) {
    stop("`csljson` does not exist: ", csljson)
  }

  if (dir.exists(csljson)) {
    # Directory (chunked) inputs
    if (to %in% c("bibtex", "biblatex")) {
      return(
        .convert_dir_bib(
          csljson_dir = csljson,
          output_dir = output,
          to = to,
          overwrite = overwrite,
          verbose = verbose
        )
      )
    }
    if (to %in% c("docx", "markdown", "latex", "html", "pdf")) {
      return(
        .render_dir_formatted(
          csljson_dir = csljson,
          output_dir = output,
          to = to,
          overwrite = overwrite,
          verbose = verbose,
          references_csl = references_csl,
          pdf_engine = pdf_engine,
          pdf_mainfont = pdf_mainfont,
          pdf_sansfont = pdf_sansfont,
          pdf_monofont = pdf_monofont,
          pdf_cjk_mainfont = pdf_cjk_mainfont,
          pdf_cjk_options = pdf_cjk_options
        )
      )
    }
    stop("Unsupported 'to' value: ", to)
  }

  # Single-file inputs
  input_file <- normalizePath(csljson, mustWork = TRUE)
  if (to %in% c("bibtex", "biblatex")) {
    return(
      .convert_file_bib(
        input_file = input_file,
        output = output,
        to = to,
        overwrite = overwrite,
        verbose = verbose
      )
    )
  }
  if (to %in% c("docx", "markdown", "latex", "html", "pdf")) {
    return(
      .render_file_formatted(
        input_file = input_file,
        output = output,
        to = to,
        overwrite = overwrite,
        verbose = verbose,
        references_csl = references_csl,
        pdf_engine = pdf_engine,
        pdf_mainfont = pdf_mainfont,
        pdf_sansfont = pdf_sansfont,
        pdf_monofont = pdf_monofont,
        pdf_cjk_mainfont = pdf_cjk_mainfont,
        pdf_cjk_options = pdf_cjk_options
      )
    )
  }
  stop("Unsupported 'to' value: ", to)
}

# -----------------------------------------------------------------------------
# Internal helpers (non-exported)
# -----------------------------------------------------------------------------

#' Ensure rmarkdown/pandoc are available
#' @noRd
.check_pandoc_ready <- function() {
  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop(
      paste(
        "Package 'rmarkdown' is required for Pandoc conversion.",
        "Please install it."
      )
    )
  }
  if (!rmarkdown::pandoc_available()) {
    stop(
      "Pandoc is not available. Install Pandoc or use RStudio (bundled Pandoc)."
    )
  }
}

#' Normalize/sanitize a CSL JSON file for pandoc
#' - Re-serializes JSON for consistent encoding
#' - Optionally removes very long abstracts (> cap) to avoid pandoc/LaTeX stalls
#' Returns a list(path, sanitized_flag). Path may be a temp file.
#' @noRd
.normalize_json_for_pandoc <- function(
  path,
  drop_long_abstracts = TRUE,
  cap = 10000
) {
  in_use <- normalizePath(path, mustWork = TRUE)
  tmp_in <- tempfile(fileext = ".json")
  sanitized <- FALSE
  ok <- tryCatch({
    j <- jsonlite::fromJSON(in_use, simplifyVector = FALSE)
    if (isTRUE(drop_long_abstracts) && is.list(j)) {
      if (!is.null(j) && length(j) > 0 && is.null(names(j))) {
        for (kk in seq_along(j)) {
          it <- j[[kk]]
          if (
            is.list(it) &&
              !is.null(it$abstract) &&
              is.character(it$abstract)
          ) {
            ab <- it$abstract
            if (length(ab) == 1L && nchar(ab, allowNA = FALSE) > cap) {
              it$abstract <- NULL
              j[[kk]] <- it
              sanitized <- TRUE
            }
          }
        }
      } else if (!is.null(j$abstract) && is.character(j$abstract)) {
        if (nchar(j$abstract, allowNA = FALSE) > cap) {
          j$abstract <- NULL
          sanitized <- TRUE
        }
      }
    }
    jsonlite::toJSON(j, auto_unbox = TRUE) |> writeLines(con = tmp_in)
    TRUE
  }, error = function(e) FALSE)
  if (ok) in_use <- tmp_in
  list(path = in_use, sanitized = sanitized)
}

#' Build pandoc options for formatted outputs
#' @noRd
.build_pandoc_options <- function(
  to,
  bibliography_files,
  references_csl = NULL,
  pdf_engine = "xelatex",
  pdf_mainfont = NULL,
  pdf_sansfont = NULL,
  pdf_monofont = NULL,
  pdf_cjk_mainfont = NULL,
  pdf_cjk_options = NULL
) {
  extra <- c("--citeproc", paste0("--bibliography=", bibliography_files))
  if (identical(to, "html")) {
    extra <- c(extra, "--standalone")
  }
  if (identical(to, "pdf")) {
    if (!is.null(pdf_engine)) {
      extra <- c(extra, paste0("--pdf-engine=", pdf_engine))
    }
    add_font <- function(var, val) {
      if (!is.null(val) && nzchar(val)) {
        extra <<- c(extra, "-V", paste0(var, "=", val))
      }
    }
    add_font("mainfont", pdf_mainfont)
    add_font("sansfont", pdf_sansfont)
    add_font("monofont", pdf_monofont)
    add_font("CJKmainfont", pdf_cjk_mainfont)
    add_font("CJKoptions", pdf_cjk_options)
  }
  if (!is.null(references_csl)) {
    extra <- c(extra, paste0("--csl=", references_csl))
  }
  extra
}

#' Write a minimal Markdown document that includes all refs
#' @noRd
.write_refs_md <- function() {
  md <- tempfile(fileext = ".md")
  cat(
    paste0(
      "---\n",
      "nocite: \"@*\"\n",
      "---\n\n",
      "# References\n\n",
      "::: {#refs}\n",
      ":::\n"
    ),
    file = md
  )
  md
}

#' Ensure output directory exists and return absolute path
#' @noRd
.ensure_dir <- function(path) {
  if (file.exists(path) && !dir.exists(path)) {
    stop("`output` must be a directory when converting a directory of chunks.")
  }
  if (!dir.exists(path)) {
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!ok || !dir.exists(path)) {
      stop("Could not create output directory: ", path)
    }
  }
  normalizePath(path, mustWork = TRUE)
}

#' Convert a directory of chunked JSONs to bibtex/biblatex files
#' @noRd
.convert_dir_bib <- function(csljson_dir, output_dir, to, overwrite, verbose) {
  in_dir <- normalizePath(csljson_dir, mustWork = TRUE)
  chunk_files <- list.files(
    in_dir,
    pattern = "^chunk_\\d+\\.json$",
    full.names = TRUE
  )
  if (!length(chunk_files)) {
    stop("No chunk_*.json files found in ", csljson_dir)
  }
  out_dir <- .ensure_dir(output_dir)
  ext <- switch(to, bibtex = ".bib", biblatex = ".bib")
  out_files <- character(length(chunk_files))
  for (i in seq_along(chunk_files)) {
    in_f <- normalizePath(chunk_files[i], mustWork = TRUE)
    base <- sub("\\.json$", "", basename(in_f))
    out_f <- file.path(out_dir, paste0(base, ext))
    if (file.exists(out_f)) {
      if (!overwrite) {
        stop(
          "Output file exists: ",
          out_f,
          ". Set overwrite = TRUE to replace."
        )
      }
      unlink(out_f)
    }
    norm <- .normalize_json_for_pandoc(
      in_f,
      drop_long_abstracts = TRUE,
      cap = 10000
    )
    if (isTRUE(verbose)) {
      message(
        "Converting with pandoc: ", basename(in_f), " -> ", basename(out_f),
        " (", to, ")", if (norm$sanitized) " [sanitized]" else ""
      )
    }
    rmarkdown::pandoc_convert(
      input = norm$path,
      to = to,
      from = "csljson",
      output = out_f
    )
    out_files[i] <- out_f
  }
  invisible(normalizePath(out_files, mustWork = FALSE))
}

#' Render formatted refs from a directory of chunked JSONs
#' @noRd
.render_dir_formatted <- function(
  csljson_dir,
  output_dir,
  to,
  overwrite,
  verbose,
  references_csl,
  pdf_engine,
  pdf_mainfont,
  pdf_sansfont,
  pdf_monofont,
  pdf_cjk_mainfont,
  pdf_cjk_options
) {
  in_dir <- normalizePath(csljson_dir, mustWork = TRUE)
  chunk_files <- list.files(
    in_dir,
    pattern = "^chunk_\\d+\\.json$",
    full.names = TRUE
  )
  if (!length(chunk_files)) {
    stop("No chunk_*.json files found in ", csljson_dir)
  }
  extra <- .build_pandoc_options(
    to = to,
    bibliography_files = normalizePath(chunk_files, mustWork = TRUE),
    references_csl = references_csl,
    pdf_engine = pdf_engine,
    pdf_mainfont = pdf_mainfont,
    pdf_sansfont = pdf_sansfont,
    pdf_monofont = pdf_monofont,
    pdf_cjk_mainfont = pdf_cjk_mainfont,
    pdf_cjk_options = pdf_cjk_options
  )
  md <- .write_refs_md()
  out_dir <- .ensure_dir(output_dir)
  ext <- switch(
    to,
    docx = ".docx",
    markdown = ".md",
    latex = ".tex",
    html = ".html",
    pdf = ".pdf"
  )
  refs_out <- file.path(out_dir, paste0("references", ext))
  if (file.exists(refs_out)) {
    if (!overwrite) {
      stop(
        "Output file exists: ",
        refs_out,
        ". Set overwrite = TRUE to replace."
      )
    }
    unlink(refs_out)
  }
  if (isTRUE(verbose)) {
    message(
      "Rendering formatted references: ",
      basename(refs_out),
      " (",
      to,
      ")"
    )
  }
  rmarkdown::pandoc_convert(
    input = md,
    to = to,
    from = "markdown",
    output = refs_out,
    options = c(extra)
  )
  if (identical(to, "markdown")) {
    try({
      txt <- readLines(refs_out, warn = FALSE, encoding = "UTF-8")
      keep <- !grepl("^:{3,}\\s*(\\{.*\\})?$", txt)
      writeLines(txt[keep], refs_out, useBytes = TRUE)
    }, silent = TRUE)
  }
  invisible(normalizePath(refs_out, mustWork = FALSE))
}

#' Convert a single CSL JSON file to bibtex/biblatex
#' @noRd
.convert_file_bib <- function(input_file, output, to, overwrite, verbose) {
  out_file <- output
  if (nzchar(out_file) && identical(tools::file_ext(out_file), "")) {
    out_file <- paste0(out_file, ".bib")
  }
  out_dir <- dirname(out_file)
  if (!identical(out_dir, ".") && !dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (file.exists(out_file)) {
    if (!overwrite) stop("Output file exists: ", out_file)
    unlink(out_file)
  }
  if (isTRUE(verbose)) {
    message(
      "Converting with pandoc: ",
      basename(input_file),
      " -> ",
      basename(out_file),
      " (", to, ")"
    )
  }
  norm <- .normalize_json_for_pandoc(input_file, drop_long_abstracts = FALSE)
  rmarkdown::pandoc_convert(
    input = norm$path,
    to = to,
    from = "csljson",
    output = out_file
  )
  invisible(normalizePath(out_file, mustWork = FALSE))
}

#' Render formatted refs from a single CSL JSON file
#' @noRd
.render_file_formatted <- function(
  input_file,
  output,
  to,
  overwrite,
  verbose,
  references_csl,
  pdf_engine,
  pdf_mainfont,
  pdf_sansfont,
  pdf_monofont,
  pdf_cjk_mainfont,
  pdf_cjk_options
) {
  extra <- .build_pandoc_options(
    to = to,
    bibliography_files = input_file,
    references_csl = references_csl,
    pdf_engine = pdf_engine,
    pdf_mainfont = pdf_mainfont,
    pdf_sansfont = pdf_sansfont,
    pdf_monofont = pdf_monofont,
    pdf_cjk_mainfont = pdf_cjk_mainfont,
    pdf_cjk_options = pdf_cjk_options
  )
  md <- .write_refs_md()
  refs_out <- output
  if (identical(tools::file_ext(refs_out), "")) {
    ext <- switch(
    to,
    docx = ".docx",
    markdown = ".md",
    latex = ".tex",
    html = ".html",
    pdf = ".pdf"
  )
    refs_out <- paste0(refs_out, ext)
  }
  rd <- dirname(refs_out)
  if (!identical(rd, ".") && !dir.exists(rd)) {
    dir.create(rd, recursive = TRUE, showWarnings = FALSE)
  }
  refs_out <- normalizePath(refs_out, mustWork = FALSE)
  if (file.exists(refs_out)) {
    if (!overwrite) stop("Output file exists: ", refs_out)
    unlink(refs_out)
  }
  if (isTRUE(verbose)) {
    message(
      "Rendering formatted references: ",
      basename(refs_out),
      " (",
      to,
      ")"
    )
  }
  rmarkdown::pandoc_convert(
    input = md,
    to = to,
    from = "markdown",
    output = refs_out,
    options = c(extra)
  )
  if (identical(to, "markdown")) {
    try({
      txt <- readLines(refs_out, warn = FALSE, encoding = "UTF-8")
      keep <- !grepl("^:{3,}\\s*(\\{.*\\})?$", txt)
      writeLines(txt[keep], refs_out, useBytes = TRUE)
    }, silent = TRUE)
  }
  invisible(normalizePath(refs_out, mustWork = FALSE))
}
