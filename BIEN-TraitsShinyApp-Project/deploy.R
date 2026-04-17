suppressWarnings(library(rsconnect))

# Optional: set account info once in your environment/session.
# rsconnect::setAccountInfo(name = "benquist", token = "<TOKEN>", secret = "<SECRET>")

cat("Deploying BIEN Traits Shiny App to shinyapps.io...\n")
rsconnect::deployApp(
  appDir = ".",
  appName = "bien-traits-shinyapp",
  account = "benquist",
  forceUpdate = TRUE,
  launch.browser = FALSE
)
cat("Deployment complete.\n")
