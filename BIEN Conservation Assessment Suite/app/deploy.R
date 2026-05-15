suppressWarnings(library(rsconnect))
rsconnect::deployApp(
  appDir       = "/Users/brianjenquist/VSCode/BIEN Conservation Assessment Suite/app",
  appName      = "bien-conservation-assessment",
  account      = "benquist",
  launch.browser = FALSE
)
