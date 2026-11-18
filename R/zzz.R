.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "
      This package is in alpha phase and will likely change!

      Use at own risk (as usual)!
    "
  )
}
