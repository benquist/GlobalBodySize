test_that("join QC smoke: audit flags bad join and qc catches issues", {
  obs <- data.frame(
    species_name = c("Abies bracteata", ""),
    plot_id = c("P1", "P2"),
    observed_on = c("1901-01-04", "bad-date"),
    stringsAsFactors = FALSE
  )

  meta <- data.frame(
    site = c("P1", "P2", "P2"),
    latitude = c(34.2, 120, 35.1),
    longitude = c(-119.7, -200, -120.1),
    stringsAsFactors = FALSE
  )

  files <- list(obs = obs, meta = meta)
  keys <- list(meta = "site")

  audit <- audit_join_quality(files, "obs", "plot_id", c("meta"), keys)
  expect_equal(nrow(audit), 1L)

  merged <- merge_uploaded_streams(files, "obs", "plot_id", c("meta"), keys)
  map <- data.frame(
    source_column = c("species_name", "observed_on", "latitude", "longitude"),
    dwc_term = c("scientificName", "eventDate", "decimalLatitude", "decimalLongitude"),
    stringsAsFactors = FALSE
  )

  dwc <- apply_dwc_mapping(merged, map)
  qc <- run_dwc_qc(dwc)
  expect_gte(nrow(qc), 1L)
})
