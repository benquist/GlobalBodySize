test_that("join blocker and service-state smoke tests pass", {
  pkg <- "LoadingHistoricalObservationDataIntoBIEN"

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
  expect_equal(nrow(audit), 1L)
  expect_equal(audit$join_cardinality[[1]], "many-to-many")
  expect_true(getFromNamespace("has_join_blockers", pkg)(audit))

  counted_coords <- getFromNamespace("count_basic_valid_coordinates", pkg)(c(TRUE, FALSE, NA, TRUE, "TRUE"))
  expect_true(identical(counted_coords, 3L) || identical(counted_coords, 3))

  export_gate_err <- tryCatch({
    getFromNamespace("ensure_join_clear_for_export", pkg)(audit, "BIEN Loading Draft")
    NULL
  }, error = function(e) e)
  expect_s3_class(export_gate_err, "error")
  expect_true(grepl("Cannot download BIEN Loading Draft", conditionMessage(export_gate_err), fixed = TRUE))

  local_state <- getFromNamespace("summarize_bien_service_state", pkg)(
    "GNRS",
    getFromNamespace("bien_gnrs_query", pkg)(meta),
    authoritative = FALSE
  )
  expect_true(grepl("not authoritative", local_state, fixed = TRUE))

  auth_state <- getFromNamespace("summarize_bien_service_state", pkg)(
    "TNRS",
    data.frame(submitted_name = "Abies bracteata", stringsAsFactors = FALSE),
    authoritative = TRUE
  )
  expect_true(grepl("pending expert review", auth_state, fixed = TRUE))
})
