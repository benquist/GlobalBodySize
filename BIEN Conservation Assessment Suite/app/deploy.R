## deploy.R ── Staged self-contained deployment to shinyapps.io
##
## rsconnect follows "../" relative paths in source() calls, sweeping in the
## entire workspace (10,000+ files). This script copies every needed file into
## a flat temp bundle with all paths rewritten to be intra-bundle before deploy.

suppressWarnings(library(rsconnect))

## Resolve project root regardless of how this script is invoked
ROOT <- normalizePath(
  file.path(dirname(normalizePath("app/deploy.R", mustWork = FALSE)), ".."),
  mustWork = FALSE
)
if (!dir.exists(ROOT)) {
  ROOT <- normalizePath(".", mustWork = TRUE)
}
message("Project root: ", ROOT)
BUNDLE <- file.path(tempdir(), paste0("bien_deploy_", format(Sys.time(), "%Y%m%d%H%M%S")))
dir.create(BUNDLE, recursive = TRUE)
message("Bundle dir: ", BUNDLE)

## ── Helper ────────────────────────────────────────────────────────────────────
cp <- function(src_rel, dest_rel = src_rel) {
  src  <- file.path(ROOT, src_rel)
  dest <- file.path(BUNDLE, dest_rel)
  if (!file.exists(src)) { warning("Missing: ", src); return(invisible(NULL)) }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest, overwrite = TRUE)
}

## ── Copy app files ────────────────────────────────────────────────────────────
cp("app/app.R",       "app.R")
cp("app/global.R",    "global.R")

for (f in list.files(file.path(ROOT, "modules"), pattern = "\\.R$")) {
  cp(file.path("modules", f), file.path("modules", f))
}
for (f in list.files(file.path(ROOT, "utils"), pattern = "\\.R$")) {
  cp(file.path("utils", f), file.path("utils", f))
}

cp("www/disclaimer.html",                      "www/disclaimer.html")
cp("report_template/report.Rmd",               "report_template/report.Rmd")
cp("data/Japura_AOI_Nov2025_mapshaper.json",   "data/Japura_AOI_Nov2025_mapshaper.json")

## ── Rewrite global.R paths (../x → ./x) ──────────────────────────────────────
bundle_global <- file.path(BUNDLE, "global.R")
txt <- readLines(bundle_global, warn = FALSE)
txt <- gsub('"\\.\\./', '"', txt, fixed = FALSE)  # "../modules" → "modules" etc.
writeLines(txt, bundle_global)

## ── Rewrite app.R paths ───────────────────────────────────────────────────────
bundle_app <- file.path(BUNDLE, "app.R")
txt <- readLines(bundle_app, warn = FALSE)
txt <- gsub('"\\.\\./', '"', txt, fixed = FALSE)
writeLines(txt, bundle_app)

message("Bundle contents:")
print(list.files(BUNDLE, recursive = TRUE))

## ── Deploy ────────────────────────────────────────────────────────────────────
rsconnect::deployApp(
  appDir         = BUNDLE,
  appName        = "bien-conservation-assessment",
  account        = "benquist",
  launch.browser = FALSE,
  forceUpdate    = TRUE
)

