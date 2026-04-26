ingest_leda_manifest <- function(manifest_path, output_dir, candidate_score_default = 0.5, candidate_keep_default = TRUE) {
  ingest_impl <- get0("provider_ingest_manifest", mode = "function")
  if (is.null(ingest_impl)) {
    stop("provider_ingest_manifest is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
  }

  ingest_impl(
    provider_name = "leda",
    manifest_path = manifest_path,
    output_dir = output_dir,
    candidate_score_default = candidate_score_default,
    candidate_keep_default = candidate_keep_default
  )
}
