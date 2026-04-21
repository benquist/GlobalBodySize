runApp <- function(...) {
  app_dir <- system.file("app", package = "BIENSpeciesShinyApp")
  if (!nzchar(app_dir)) {
    stop("Bundled app directory not found inside the installed package.")
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(app_dir)

  shiny::runApp(appDir = app_dir, ...)
}
