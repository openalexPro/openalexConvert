# Regenerate the comparison fixtures under tests/fixtures/.
#
# Run from the package root, in a UTF-8 locale:
#
#   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript data-raw/regenerate_fixtures.R
#
# The locale is not optional. In a C locale R renders non-ASCII author names
# as literal "<U+00F3>" escapes, and pandoc then writes
# "Bay\textless U+00F3\textgreater n" into the .bib fixtures. That is how a
# broken fixture gets committed and then quietly becomes the expectation.
#
# `references.docx` is deliberately not regenerated: it is binary, nothing
# compares its contents, and rewriting it only adds churn.

stopifnot(grepl("UTF-8", Sys.getlocale("LC_CTYPE"), fixed = TRUE))
devtools::load_all(".", quiet = TRUE)

fixtures <- "tests/fixtures"
corpus   <- file.path(fixtures, "corpus")

message("CSL-JSON ...")
csl <- file.path(fixtures, "corpus_csl")
unlink(list.files(csl, pattern = "[.]json$", full.names = TRUE))
corpus_to_csljson(corpus = corpus, output = csl, chunk_size = 100,
                  overwrite = TRUE, verbose = FALSE)

for (fmt in c("bibtex", "biblatex")) {
  message(fmt, " ...")
  out <- file.path(fixtures, paste0("corpus_", fmt))
  unlink(list.files(out, pattern = "[.]bib$", full.names = TRUE))
  csljson_convert_pandoc(csl, out, to = fmt, overwrite = TRUE, verbose = FALSE)
}

docs <- file.path(fixtures, "corpus_docs")
for (fmt in c("markdown", "latex")) {
  message(fmt, " ...")
  tmp <- tempfile(fmt); dir.create(tmp)
  p <- csljson_convert_pandoc(csl, tmp, to = fmt, overwrite = TRUE,
                              verbose = FALSE)
  file.copy(p, file.path(docs, basename(p)), overwrite = TRUE)
  unlink(tmp, recursive = TRUE)
}

message("done")
