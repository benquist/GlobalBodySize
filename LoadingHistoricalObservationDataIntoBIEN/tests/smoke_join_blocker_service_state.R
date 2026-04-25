pkg_root <- tryCatch(normalizePath(file.path(dirname(sys.frame(1)$ofile), ".."), mustWork = FALSE), error = function(e) normalizePath(".."))
for (f in list.files(file.path(pkg_root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f, local = FALSE)

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


stopifnot(isTRUE(has_join_blockers(audit)))

counted_coords <- count_basic_valid_coordinates(c(TRUE, FALSE, NA, TRUE, "TRUE"))
stopifnot(identical(counted_coords, 3L) || identical(counted_coords, 3))

export_gate_err <- tryCatch({
  ensure_join_clear_for_export(audit, "BIEN Loading Draft")
  NULL
}, error = function(e) e)
stopifnot(inherits(export_gate_err, "error"))
stopifnot(grepl("Cannot download BIEN Loading Draft", conditionMessage(export_gate_err), fixed = TRUE))
local_state <- summarize_bien_service_state(
  "GNRS",
  bien_gnrs_query(meta),
  authoritative = FALSE
)
stopifnot(grepl("not authoritative", local_state, fixed = TRUE))

auth_state <- summarize_bien_service_state(
  "TNRS",
  data.frame(submitted_name = "Abies bracteata", stringsAsFactors = FALSE),
  authoritative = TRUE
)
stopifnot(grepl("pending expert review", auth_state, fixed = TRUE))

cat("join blocker + service-state smoke OK\n")
