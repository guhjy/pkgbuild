#' Is Rtools installed?
#'
#' To build binary packages on windows, Rtools (found at
#' \url{https://CRAN.R-project.org/bin/windows/Rtools/}) needs to be on
#' the path. The default installation process does not add it, so this
#' script finds it (looking first on the path, then in the registry).
#' It also checks that the version of rtools matches the version of R.
#' `has_rtools()` determines if Rtools is installed, caching the results.
#' Afterward, run `rtools_path()` to find out where it's installed.
#'
#' @section Acknowledgements:
#'   This code borrows heavily from RStudio's code for finding Rtools.
#'   Thanks JJ!
#' @param debug If `TRUE`, will print out extra information useful for
#'   debugging. If `FALSE`, it will use result cached from a previous run.
#' @return Either a visible `TRUE` if rtools is found, or an invisible
#'   `FALSE` with a diagnostic [message()].
#'   As a side-effect the internal package variable `rtools_path` is
#'   updated to the paths to rtools binaries.
#' @keywords internal
#' @export
#' @examples
#' has_rtools()
has_rtools <- function(debug = FALSE) {
  if (!debug && rtools_path_is_set())
    return(!identical(rtools_path(), ""))

  if (!is_windows())
    return(FALSE)

  # First, R CMD config CC --------------------------------------------
  from_config <- scan_config_for_rtools(debug)
  if (is_compatible(from_config)) {
    if (debug)
      cat("Found compatible gcc from R CMD config CC\n")
    rtools_path_set(from_config)
    return(TRUE)
  }

  # Next, try the path ------------------------------------------------
  from_path <- scan_path_for_rtools(debug)
  if (is_compatible(from_path)) {
    if (debug)
      cat("Found compatible gcc on path\n")
    rtools_path_set(from_path)
    return(TRUE)
  }

  if (!is.null(from_path)) {
    # Installed
    if (is.null(from_path$version)) {
      # but not from rtools
      if (debug)
        cat("gcc and ls on path, assuming set up is correct\n")
      return(TRUE)
    } else {
      # Installed, but not compatible
      message("WARNING: Rtools ", from_path$version, " found on the path",
        " at ", from_path$path, " is not compatible with R ", getRversion(), ".\n\n",
        "Please download and install ", rtools_needed(), " from ", rtools_url,
        ", remove the incompatible version from your PATH.")
      return(invisible(FALSE))
    }
  }

  # Next, try the registry --------------------------------------------------
  registry_candidates <- scan_registry_for_rtools(debug)

  if (length(registry_candidates) == 0) {
    # Not on path or in registry, so not installled
    message("WARNING: Rtools is required to build R packages, but is not ",
      "currently installed.\n\n",
      "Please download and install ", rtools_needed(), " from ", rtools_url, ".")
    return(invisible(FALSE))
  }

  from_registry <- Find(is_compatible, registry_candidates, right = TRUE)
  if (is.null(from_registry)) {
    # In registry, but not compatible.
    versions <- vapply(registry_candidates, function(x) x$version, character(1))
    message("WARNING: Rtools is required to build R packages, but no version ",
      "of Rtools compatible with R ", getRversion(), " was found. ",
      "(Only the following incompatible version(s) of Rtools were found:",
      paste(versions, collapse = ","), ")\n\n",
      "Please download and install ", rtools_needed(), " from ", rtools_url, ".")
    return(invisible(FALSE))
  }

  installed_ver <- installed_version(from_registry$path, debug = debug)
  if (is.null(installed_ver)) {
    # Previously installed version now deleted
    message("WARNING: Rtools is required to build R packages, but the ",
      "version of Rtools previously installed in ", from_registry$path,
      " has been deleted.\n\n",
      "Please download and install ", rtools_needed(), " from ", rtools_url, ".")
    return(invisible(FALSE))
  }

  if (installed_ver != from_registry$version) {
    # Installed version doesn't match registry version
    message("WARNING: Rtools is required to build R packages, but no version ",
      "of Rtools compatible with R ", getRversion(), " was found. ",
      "Rtools ", from_registry$version, " was previously installed in ",
      from_registry$path, " but now that directory contains Rtools ",
      installed_ver, ".\n\n",
      "Please download and install ", rtools_needed(), " from ", rtools_url, ".")
    return(invisible(FALSE))
  }

  # Otherwise it must be ok :)
  rtools_path_set(from_registry)
  TRUE
}

#' @rdname has_rtools
#' @usage NULL
#' @export
find_rtools <- has_rtools

#' @rdname has_rtools
#' @usage NULL
#' @export
setup_rtools <- has_rtools

#' @export
#' @rdname has_rtools
check_rtools <- function(debug = FALSE) {
  if (is_windows() && !has_rtools(debug = debug))
    stop("Rtools is not installed.", call. = FALSE)

  TRUE
}

installed_version <- function(path, debug) {
  if (!file.exists(file.path(path, "Rtools.txt"))) return(NULL)

  # Find the version path
  version_path <- file.path(path, "VERSION.txt")
  if (debug) {
    cat("VERSION.txt\n")
    cat(readLines(version_path), "\n")
  }
  if (!file.exists(version_path)) return(NULL)

  # Rtools is in the path -- now crack the VERSION file
  contents <- NULL
  try(contents <- readLines(version_path), silent = TRUE)
  if (is.null(contents)) return(NULL)

  # Extract the version
  contents <- gsub("^\\s+|\\s+$", "", contents)
  version_re <- "Rtools version (\\d\\.\\d+)\\.[0-9.]+$"

  if (!grepl(version_re, contents)) return(NULL)

  m <- regexec(version_re, contents)
  regmatches(contents, m)[[1]][2]
}

is_compatible <- function(rtools) {
  if (is.null(rtools)) return(FALSE)
  if (is.null(rtools$version)) return(FALSE)

  stopifnot(is.rtools(rtools))
  info <- version_info[[rtools$version]]
  if (is.null(info)) return(FALSE)

  r_version <- getRversion()
  r_version >= info$version_min && r_version <= info$version_max
}

rtools <- function(path, version, ...) {
  structure(list(version = version, path = path, ...), class = "rtools")
}
is.rtools <- function(x) inherits(x, "rtools")

rtools_needed <- function() {
  r_version <- getRversion()

  for (i in rev(seq_along(version_info))) {
    version <- names(version_info)[i]
    info <- version_info[[i]]
    ok <- r_version >= info$version_min && r_version <= info$version_max
    if (ok)
      return(paste("Rtools", version))
  }
  "the appropriate version of Rtools"
}

rtools_url <- "http://cran.r-project.org/bin/windows/Rtools/"
