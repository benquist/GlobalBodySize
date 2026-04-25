if (!requireNamespace("LoadingHistoricalObservationDataIntoBIEN", quietly = TRUE)) {
  .libPaths(c(normalizePath("../..")), .libPaths())
}
library(LoadingHistoricalObservationDataIntoBIEN)

obs <- data.frame(
  plot_id = c("P1", "P1", "P2", "P2"),
  scientific_name = c("Abies bracteata", "Pinus ponderosa", "Quercus agrifolia", "Pseudotsuga menziesii"),
  stringsAsFactors = FALSE
)

meta <- data.frame(
  site_id = c("P1", "P1", "P2", "P2"),
  locality = c("Loc A", "Loc A duplicate", "Loc B", "Loc B duplicate"),
  country = c("United States", "United States", "United States", "United States"),
  stringsAsFactors = FALSE
)

files <- list(obs = obs, meta = meta)
keys <- list(meta = "site_id")

audit <- audit_join_quality(files, "obs", "plot_id", c("meta"), keys)
stopifnot(nrow(audit) == 1)
stopifnot(audit$join_cardinality[[1]] == "many-to-many")
pkg <- "LoadingHistoricalObservationDataIntoBIEN"
stopifnot(isTRUE(getFromNamespace("has_join_blockers", pkg)(audit)))

counted_coords <- getFromNamespace("count_basic_valid_coordinates", pkg)(c(TRUE, FALSE, NA, TRUE, "TRUE"))
stopifnot(identical(counted_coords, 3L) || identical(counted_coords, 3))

export_gate_err <- tryCatch({
  getFromNamespace("ensure_join_clear_for_export", pkg)(audit, "BIEN Loading Draft")
  NULL
}, error = function(e) e)
stopifnot(inherits(export_gate_err, "error"))
stopifnot(grepl("Cannot download BIEN Loading Draft", conditionMessage(export_gate_err), fixed = TRUE))

local_state <- getFromNamespace("summarize_bien_service_state", pkg)(
  "GNRS",
  getFromNamespace("bien_gnrs_query", pkg)(meta),
  authoritative = FALSE
)
stopifnot(grepl("not authoritative", local_state, fixed = TRUE))

auth_state <- getFromNamespace("summarize_bien_service_state", pkg)(
  "TNRS",
  data.frame(submitted_name = "Abies bracteata", stringsAsFactors = FALSE),
  authoritative = TRUE
)
stopifnot(grepl("pending expert review", auth_state, fixed = TRUE))

cat("join blocker + service-state smoke OK\n")
