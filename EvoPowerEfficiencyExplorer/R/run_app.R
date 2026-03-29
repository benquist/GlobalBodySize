#' Run the Evo Power Efficiency Shiny App
#'
#' Launches the interactive Shiny app bundled with this package.
#'
#' @return Runs a Shiny application.
#' @export
run_EvoPowerEfficiency_app <- function() {
  app_dir <- system.file("shiny-examples", "EvoPowerEfficiencyExplorer", package = "EvoPowerEfficiencyExplorer")
  if (app_dir == "") {
    stop("Could not find app directory. Reinstall the package.", call. = FALSE)
  }

  shiny::runApp(app_dir, display.mode = "normal")
}
