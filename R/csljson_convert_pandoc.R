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
#' @param overwrite Logical; overwrite existing output file(s). Defaults to FALSE.
#' @param verbose Print progress messages.
#' @param references_csl Optional path to a CSL style file (e.g., apa.csl). If
#'   NULL, Pandoc's default style is used.
#' @param pdf_engine LaTeX engine used when `to = "pdf"`. Common values are
#'   `"xelatex"` (default, good Unicode support), `"lualatex"`, or
#'   `"pdflatex"`. Passed to Pandoc as `--pdf-engine`.
#' @param pdf_mainfont Main text font name for PDF output (used with XeLaTeX/LuaLaTeX).
#'   Sets Pandoc variable `mainfont` (e.g., `-V mainfont=Source Serif Pro`).
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
#' Use these to ensure Unicode coverage and consistent typography, especially for
#' multilingual bibliographies.
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
  if (!file.exists(csljson)) {
    stop("`csljson` does not exist: ", csljson)
  }
  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop(
      "Package 'rmarkdown' is required for Pandoc conversion. Please install it."
    )
  }
  if (!rmarkdown::pandoc_available()) {
    stop(
      "Pandoc is not available. Install Pandoc or use RStudio (bundled Pandoc)."
    )
  }
  # If a directory is provided, handle chunked inputs
  if (dir.exists(csljson)) {
    in_dir <- normalizePath(csljson, mustWork = TRUE)
    chunk_files <- list.files(
      in_dir,
      pattern = "^chunk_\\d+\\.json$",
      full.names = TRUE
    )
    if (!length(chunk_files)) {
      stop("No chunk_*.json files found in ", csljson)
    }
    if (to %in% c("bibtex", "biblatex")) {
      # Ensure output is a directory
      out_dir <- output
      if (file.exists(out_dir)) {
        if (!dir.exists(out_dir)) {
          stop(
            "`output` must be a directory when converting a directory of chunks."
          )
        }
      } else {
        dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      }
      out_dir <- normalizePath(out_dir, mustWork = TRUE)
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
        # Normalize and sanitize JSON to avoid edge cases that can stall Pandoc
        in_use <- in_f
        tmp_in <- tempfile(fileext = ".json")
        sanitized <- FALSE
        try(
          {
            j <- jsonlite::fromJSON(in_f, simplifyVector = FALSE)
            if (is.list(j)) {
              # If it's an array of items, iterate and drop excessively long abstracts
              if (!is.null(j) && length(j) > 0 && is.null(names(j))) {
                for (kk in seq_along(j)) {
                  it <- j[[kk]]
                  if (
                    is.list(it) &&
                      !is.null(it$abstract) &&
                      is.character(it$abstract)
                  ) {
                    ab <- it$abstract
                    if (
                      length(ab) == 1L && nchar(ab, allowNA = FALSE) > 10000
                    ) {
                      it$abstract <- NULL
                      j[[kk]] <- it
                      sanitized <- TRUE
                    }
                  }
                }
              } else if (!is.null(j$abstract) && is.character(j$abstract)) {
                if (nchar(j$abstract, allowNA = FALSE) > 10000) {
                  j$abstract <- NULL
                  sanitized <- TRUE
                }
              }
            }
            # Always re-serialize to normalized JSON; use sanitized content if applicable
            jsonlite::toJSON(j, auto_unbox = TRUE) |> writeLines(con = tmp_in)
            in_use <- tmp_in
          },
          silent = TRUE
        )
        if (verbose) {
          message(
            "Converting with pandoc: ",
            basename(in_f),
            " -> ",
            basename(out_f),
            " (",
            to,
            ")",
            if (sanitized) " [sanitized]" else ""
          )
        }
        rmarkdown::pandoc_convert(
          input = in_use,
          to = to,
          from = "csljson",
          output = out_f
        )
        out_files[i] <- out_f
      }
      return(invisible(normalizePath(out_files, mustWork = FALSE)))
    }
    if (to %in% c("docx", "markdown", "latex", "html", "pdf")) {
      # Build pandoc options: citeproc + multiple --bibliography flags
      bib_opts <- paste0(
        "--bibliography=",
        normalizePath(chunk_files, mustWork = TRUE)
      )
      extra <- c("--citeproc", bib_opts)
      if (identical(to, "html")) {
        # Ensure UTF-8 meta charset and full HTML head/body
        extra <- c(extra, "--standalone")
      }
      if (identical(to, "pdf")) {
        # Use Unicode-capable engine (default xelatex) and optional fonts
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
      if (identical(to, "pdf")) {
        # Use a Unicode-capable LaTeX engine
        extra <- c(extra, "--pdf-engine=xelatex")
      }
      if (!is.null(references_csl)) {
        extra <- c(extra, paste0("--csl=", references_csl))
      }
      # Prepare a minimal markdown that asks citeproc to include all entries
      # via YAML nocite and provides a refs placeholder
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
      # Determine output file inside the output directory
      out_dir <- output
      # Ensure `output` is a directory path (create if missing; error if a file)
      if (file.exists(out_dir) && !dir.exists(out_dir)) {
        stop(
          "`output` must be a directory when converting a directory of chunks."
        )
      }
      if (!dir.exists(out_dir)) {
        ok <- dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
        if (!ok || !dir.exists(out_dir)) {
          stop("Could not create output directory: ", out_dir)
        }
      }
      ext <- switch(
        to,
        docx = ".docx",
        markdown = ".md",
        latex = ".tex",
        html = ".html",
        pdf = ".pdf"
      )
      # Normalize out_dir to absolute path for Pandoc's working directory
      out_dir <- normalizePath(out_dir, mustWork = TRUE)
      refs_out <- file.path(out_dir, paste0("references", ext))
      # Only delete the specific file if it exists and overwrite is TRUE
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
      if (verbose) {
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
      # Post-process Markdown to remove Pandoc fenced divs for a cleaner .md
      if (identical(to, "markdown")) {
        try(
          {
            txt <- readLines(refs_out, warn = FALSE, encoding = "UTF-8")
            keep <- !grepl("^:{3,}\\s*(\\{.*\\})?$", txt)
            writeLines(txt[keep], refs_out, useBytes = TRUE)
          },
          silent = TRUE
        )
      }
      return(invisible(normalizePath(refs_out, mustWork = FALSE)))
    }
    stop("Unsupported 'to' value: ", to)
  }
  # Single file case
  input_file <- normalizePath(csljson, mustWork = TRUE)
  if (to %in% c("bibtex", "biblatex")) {
    out_file <- output
    if (nzchar(out_file) && identical(tools::file_ext(out_file), "")) {
      out_file <- paste0(out_file, ".bib")
    }
    out_dir <- dirname(out_file)
    if (!identical(out_dir, ".") && !dir.exists(out_dir)) {
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    }
    if (file.exists(out_file)) {
      if (!overwrite) {
        stop("Output file exists: ", out_file)
      }
      unlink(out_file)
    }
    if (verbose) {
      message(
        "Converting with pandoc: ",
        basename(input_file),
        " -> ",
        basename(out_file),
        " (",
        to,
        ")"
      )
    }
    # Normalize JSON through jsonlite for single-file as well
    in_use <- input_file
    tmp_in <- tempfile(fileext = ".json")
    try(
      {
        j <- jsonlite::fromJSON(input_file, simplifyVector = FALSE)
        jsonlite::toJSON(j, auto_unbox = TRUE) |> writeLines(con = tmp_in)
        in_use <- tmp_in
      },
      silent = TRUE
    )
    rmarkdown::pandoc_convert(
      input = in_use,
      to = to,
      from = "csljson",
      output = out_file
    )
    return(invisible(normalizePath(out_file, mustWork = FALSE)))
  }
  if (to %in% c("docx", "markdown", "latex", "html", "pdf")) {
    extra <- c("--citeproc", paste0("--bibliography=", input_file))
    if (identical(to, "html")) {
      # Ensure UTF-8 meta charset and full HTML head/body
      extra <- c(extra, "--standalone")
    }
    if (identical(to, "pdf")) {
      # Use Unicode-capable engine (default xelatex) and optional fonts
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
    if (identical(to, "pdf")) {
      # Use a Unicode-capable LaTeX engine
      extra <- c(extra, "--pdf-engine=xelatex")
    }
    if (!is.null(references_csl)) {
      extra <- c(extra, paste0("--csl=", references_csl))
    }
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
    # Use absolute output path to avoid Pandoc writing into a temp dir
    refs_out <- normalizePath(refs_out, mustWork = FALSE)
    if (file.exists(refs_out)) {
      if (!overwrite) {
        stop("Output file exists: ", refs_out)
      }
      unlink(refs_out)
    }
    if (verbose) {
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
    # Post-process Markdown to remove Pandoc fenced divs for a cleaner .md
    if (identical(to, "markdown")) {
      try(
        {
          txt <- readLines(refs_out, warn = FALSE, encoding = "UTF-8")
          keep <- !grepl("^:{3,}\\s*(\\{.*\\})?$", txt)
          writeLines(txt[keep], refs_out, useBytes = TRUE)
        },
        silent = TRUE
      )
    }
    return(invisible(normalizePath(refs_out, mustWork = FALSE)))
  }
  stop("Unsupported 'to' value: ", to)
}
