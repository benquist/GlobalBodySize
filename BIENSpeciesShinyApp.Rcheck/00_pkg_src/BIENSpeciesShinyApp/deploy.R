suppressWarnings(library(rsconnect))

# Set account info for deployment
rsconnect::setAccountInfo(name = "benquist", 
               token = "D969F4FE6ACAC6DC43906F14E32F6E54",
               secret = "kCp4UGQG3NDDW0E6ELn8wF5eZ6Q4Bv5k6MWL3BX7jGEJCxQSiZp1R9gqZ5Jv1Znh")

# Deploy app
cat("Deploying fixed app to shinyapps.io...\n")
rsconnect::deployApp(appDir = "/Users/brianjenquist/VSCode/BIEN-SpeciesShinyApp",
          appName = "bien-species-shinyapp",
          account = "benquist",
          launch.browser = FALSE)

cat("Deployment complete!\n")
