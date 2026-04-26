#!/usr/bin/env Rscript

root_guess <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") return(dirname(cwd))
  candidate <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(candidate)) return(candidate)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- root_guess()
source(file.path(project_root, "R", "post_compile_qa", "helpers.R"), local = FALSE)
source(file.path(project_root, "R", "post_compile_qa", "species_gate.R"), local = FALSE)
source(file.path(project_root, "R", "post_compile_qa", "range_scoring.R"), local = FALSE)
source(file.path(project_root, "R", "post_compile_qa", "triage.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units_decision_tree.R"), local = FALSE)

args <- pcqa_parse_named_args(commandArgs(trailingOnly = TRUE))
input_path <- args$input %||% file.path(project_root, "output", "compiled_trait_observations.csv")
output_dir <- args$`output-dir` %||% args$output_dir %||% file.path(project_root, "output", "qa_post_compile")

dict_path <- file.path(project_root, "data", "trait_dictionary_starter.csv")

if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, call. = FALSE)
}
if (!file.exists(dict_path)) {
  stop("Trait dictionary file not found: ", dict_path, call. = FALSE)
}

pcqa_make_dir(output_dir)

message("Reading compiled observations: ", input_path)
obs <- pcqa_read_csv(input_path)

message("Running species gate...")
sg <- pcqa_apply_species_gate(obs)
pcqa_write_csv(sg$kept, file.path(output_dir, "species_kept.csv"))
pcqa_write_csv(sg$dropped, file.path(output_dir, "species_dropped.csv"))
pcqa_write_csv(sg$summary, file.path(output_dir, "species_gate_summary.csv"))

message("Reading trait dictionary: ", dict_path)
dict <- pcqa_read_csv(dict_path)

message("Scoring numeric observations against reference ranges...")
scored <- pcqa_score_observations(sg$kept, dict)

message("Applying triage rules...")
tri <- pcqa_apply_triage(scored)

pcqa_write_csv(tri$scored, file.path(output_dir, "observations_scored.csv"))
pcqa_write_csv(tri$keep, file.path(output_dir, "observations_keep.csv"))
pcqa_write_csv(tri$review, file.path(output_dir, "observations_review.csv"))
pcqa_write_csv(tri$reject, file.path(output_dir, "observations_reject.csv"))
pcqa_write_csv(tri$triage_summary, file.path(output_dir, "triage_summary.csv"))
pcqa_write_csv(tri$trait_diagnostics, file.path(output_dir, "trait_diagnostics.csv"))

# ---------------------------------------------------------------------------
# Decision-tree unit reconciliation
# ---------------------------------------------------------------------------
# Applies iu_infer_unit_by_decision_tree() to every observation, grouped by
# (dryad_dataset_doi, trait_name) so the value-distribution step uses the
# full column of values rather than one row at a time.
# Adds columns: dt_inferred_unit, dt_confidence, dt_evidence, dt_reciprocal,
#               dt_conversion_factor, dt_reason, dt_citation_keys

message("Applying decision-tree unit reconciliation to all scored observations...")

dt_apply_to_df <- function(df) {
  n <- nrow(df)
  dt_inferred_unit    <- rep(NA_character_, n)
  dt_confidence       <- rep("none",        n)
  dt_evidence         <- rep(NA_character_, n)
  dt_reciprocal       <- rep(FALSE,         n)
  dt_conversion_factor <- rep(NA_real_,     n)
  dt_reason           <- rep(NA_character_, n)
  dt_citation_keys    <- rep(NA_character_, n)

  if (!n) {
    return(cbind(df, data.frame(
      dt_inferred_unit = dt_inferred_unit,
      dt_confidence = dt_confidence,
      dt_evidence = dt_evidence,
      dt_reciprocal = dt_reciprocal,
      dt_conversion_factor = dt_conversion_factor,
      dt_reason = dt_reason,
      dt_citation_keys = dt_citation_keys,
      stringsAsFactors = FALSE
    )))
  }

  # Group key: dataset DOI + trait name + source column name
  doi_col        <- if ("dryad_dataset_doi"      %in% names(df)) df$dryad_dataset_doi      else rep(NA_character_, n)
  trait_col      <- if ("trait_name"             %in% names(df)) df$trait_name             else rep(NA_character_, n)
  col_name_col   <- if ("source_column_trait_name" %in% names(df)) df$source_column_trait_name else
                    if ("raw_trait_name"          %in% names(df)) df$raw_trait_name          else rep(NA_character_, n)
  unit_col       <- if ("unit"                   %in% names(df)) df$unit                   else rep(NA_character_, n)
  value_col      <- if ("trait_value"            %in% names(df)) df$trait_value            else rep(NA_character_, n)

  group_key <- paste(doi_col, trait_col, col_name_col, sep = "\t")
  groups    <- split(seq_len(n), group_key)
  n_groups  <- length(groups)
  done      <- 0L

  for (grp_indices in groups) {
    done <- done + 1L
    if (done %% 500L == 0L) {
      message(sprintf("  decision-tree: %d / %d groups processed...", done, n_groups))
    }
    i1 <- grp_indices[[1]]

    result <- tryCatch(
      iu_infer_unit_by_decision_tree(
        trait_name   = trait_col[[i1]],
        values       = value_col[grp_indices],
        column_name  = col_name_col[[i1]],
        unit_string  = unit_col[[i1]]
      ),
      error = function(e) {
        list(
          inferred_unit     = NA_character_,
          confidence        = "none",
          evidence          = "ERROR",
          reciprocal        = FALSE,
          conversion_factor = NA_real_,
          reason            = conditionMessage(e),
          citation_keys     = character(0)
        )
      }
    )

    dt_inferred_unit[grp_indices]    <- result$inferred_unit    %||% NA_character_
    dt_confidence[grp_indices]       <- result$confidence       %||% "none"
    dt_evidence[grp_indices]         <- result$evidence         %||% NA_character_
    dt_reciprocal[grp_indices]       <- isTRUE(result$reciprocal)
    dt_conversion_factor[grp_indices] <- result$conversion_factor %||% NA_real_
    dt_reason[grp_indices]           <- result$reason           %||% NA_character_
    dt_citation_keys[grp_indices]    <- paste(result$citation_keys %||% character(0), collapse = "; ")
  }

  cbind(df, data.frame(
    dt_inferred_unit     = dt_inferred_unit,
    dt_confidence        = dt_confidence,
    dt_evidence          = dt_evidence,
    dt_reciprocal        = dt_reciprocal,
    dt_conversion_factor = dt_conversion_factor,
    dt_reason            = dt_reason,
    dt_citation_keys     = dt_citation_keys,
    stringsAsFactors     = FALSE
  ))
}

scored_with_dt <- dt_apply_to_df(tri$scored)

message("Decision-tree reconciliation complete.")
dt_conf_tbl <- table(scored_with_dt$dt_confidence)
for (lvl in c("high", "medium", "low", "none")) {
  cnt <- if (!is.na(dt_conf_tbl[lvl])) dt_conf_tbl[[lvl]] else 0L
  message(sprintf("  dt_confidence=%s: %d rows", lvl, cnt))
}

pcqa_write_csv(scored_with_dt, file.path(output_dir, "observations_scored_with_dt.csv"))

# Write a compact unit-reconciliation summary (one row per trait)
dt_summary <- do.call(rbind, lapply(
  split(scored_with_dt, scored_with_dt$trait_name),
  function(g) {
    conf <- table(g$dt_confidence)
    data.frame(
      trait_name        = g$trait_name[[1]],
      n_obs             = nrow(g),
      dt_high           = sum(g$dt_confidence == "high",   na.rm = TRUE),
      dt_medium         = sum(g$dt_confidence == "medium", na.rm = TRUE),
      dt_low            = sum(g$dt_confidence == "low",    na.rm = TRUE),
      dt_none           = sum(g$dt_confidence == "none",   na.rm = TRUE),
      dt_reciprocal     = sum(g$dt_reciprocal,             na.rm = TRUE),
      stringsAsFactors  = FALSE
    )
  }
))
pcqa_write_csv(dt_summary, file.path(output_dir, "dt_unit_reconciliation_summary.csv"))

cat("POST_COMPILE_QA_COMPLETE\n")
cat("species_kept=", nrow(sg$kept), "\n", sep = "")
cat("species_dropped=", nrow(sg$dropped), "\n", sep = "")
cat("qa_keep=", nrow(tri$keep), "\n", sep = "")
cat("qa_review=", nrow(tri$review), "\n", sep = "")
cat("qa_reject=", nrow(tri$reject), "\n", sep = "")
cat("output_dir=", output_dir, "\n", sep = "")
