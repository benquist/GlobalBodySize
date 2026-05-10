source("R/zenodo_api.R")
query_term <- '"body mass" species dataset'
full_query  <- paste0(query_term, " AND resource_type.type:dataset")
qs  <- zenodo_compose_query(list(q = full_query, page = 1, size = 5))
url <- paste0(zenodo_api_base_url(), qs)
cat("URL:\n", url, "\n\n")

curl_path <- Sys.which("curl")
tmp <- tempfile(fileext = ".json")
cmd <- sprintf(
  '%s -s -f -H "Accept: application/json" "%s" -o "%s"',
  shQuote(curl_path), url, tmp
)
cat("CMD:\n", cmd, "\n\n")
ret <- system(cmd, ignore.stderr = FALSE)
cat("Exit code:", ret, "\n")
cat("File exists:", file.exists(tmp), "\n")
cat("File size:", if (file.exists(tmp)) file.size(tmp) else NA, "\n")
if (file.exists(tmp) && file.size(tmp) > 0) {
  parsed <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) e)
  cat("Parse result:", class(parsed), "\n")
  if (inherits(parsed, "list") && !inherits(parsed, "error")) {
    hits <- parsed[["hits"]][["hits"]]
    cat("Hits:", length(hits), "\n")
    if (length(hits)) cat("First title:", hits[[1]][["metadata"]][["title"]], "\n")
  } else {
    cat("Parse error:", conditionMessage(parsed), "\n")
    cat("Raw (first 500):\n", readLines(tmp, warn=FALSE)[1], "\n")
  }
}
