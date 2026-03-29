#' Launch the California Poppy SDM Shiny Application
#'
#' Opens an interactive Shiny dashboard for fitting and exploring a MaxEnt
#' Species Distribution Model for *Eschscholzia californica* (California
#' Poppy).  The app fetches BIEN occurrence data, loads WorldClim v2.1
#' bioclimatic variables, trains a `maxnet` model, and visualises predicted
#' habitat suitability on an interactive leaflet map with ROC curves, response
#' curves, permutation importance, and a diagnostics table.
#'
#' @param worldclim_path Character. Directory where WorldClim rasters will be
#'   downloaded / reused.  When `NULL` (default) the function first checks for
#'   a `worldclim_data/` sub-directory in the current working directory (which
#'   is present if you have already run the companion Rmd), then falls back to
#'   a temporary directory.
#' @param launch.browser Logical. Open the default browser automatically?
#'   Passed to [shiny::runApp()]. Default `TRUE`.
#' @param ... Additional arguments forwarded to [shiny::runApp()].
#'
#' @return Called for its side-effect (launches a Shiny app).
#'
#' @examples
#' \dontrun{
#'   # Re-use WorldClim data already downloaded alongside the companion Rmd
#'   run_app(worldclim_path = file.path(getwd(), "worldclim_data"))
#'
#'   # Let the app download data to a temporary directory
#'   run_app()
#' }
#'
#' @export
run_app <- function(worldclim_path = NULL, launch.browser = TRUE, ...) {
  if (is.null(worldclim_path)) {
    candidate <- file.path(getwd(), "worldclim_data")
    worldclim_path <- if (dir.exists(candidate)) candidate else file.path(tempdir(), "worldclim_data")
  }

  app_dir <- system.file("app", package = "calipoppySDM")
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    stop("Could not find the Shiny app directory. Try reinstalling 'calipoppySDM'.")
  }

  Sys.setenv(CALIPOPPY_WC_PATH = normalizePath(worldclim_path, mustWork = FALSE))
  shiny::runApp(app_dir, launch.browser = launch.browser, ...)
}
