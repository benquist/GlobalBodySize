suppressWarnings(library(rsconnect))

cat("Deploying BIEN Species Shiny App to shinyapps.io...\n\n")

# Deploy app
tryCatch({
  deployApp(
    appDir = ".",
    appName = "bien-species-shinyapp",
    account = "benquist",
    launch.browser = FALSE,
    forceUpdate = TRUE
  )
  cat("\n✓ Deployment successful!\n")
  cat("App available at: https://benquist.shinyapps.io/bien-species-shinyapp/\n")
}, error = function(e) {
  cat("✗ Deployment failed:", conditionMessage(e), "\n")
})
