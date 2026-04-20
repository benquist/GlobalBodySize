app <- source("app_gateway.R", local = TRUE)$value
if (!inherits(app, "shiny.appobj")) {
	stop("app_gateway.R did not return a shiny.appobj object.")
}

app
