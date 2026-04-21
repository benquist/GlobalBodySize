suppressWarnings(library(rsconnect))

# Deploy app using saved account info
cat("Deploying fixed app to shinyapps.io...\n")
cat("This will use your saved account credentials from ~/.rsconnect/\n")

tryCatch({
  rsconnect::deployApp(appDir = "/Users/brianjenquist/VSCode/BIEN-SpeciesShinyApp",
            appName = "bien-species-shinyapp",
            account = "benquist",
            launch.browser = FALSE)
  cat("Deployment complete!\n")
}, error = function(e) {
  cat("Deployment failed:", conditionMessage(e), "\n")
})
