#!/usr/bin/env Rscript

# generate_audit_report.R
# -----------------------------------------------------------------------
# Reads a completed dual-review audit sample CSV and produces:
#   - Reviewer agreement statistics (overall inter-rater agreement + Wilson CI)
#   - Adjudicated accuracy estimate (Wilson CI)
#   - Trait-level and dataset-level accuracy tables
#   - Error type frequency table
#   - Reviewer confusion matrix
#   - Rows flagged as needing adjudication
#
# Usage:
#   Rscript DryadPlantTraits/scripts/generate_audit_report.R \
#     --input=DryadPlantTraits/output/qa_post_compile/publication_audit_sample.csv \
#     --output-dir=DryadPlantTraits/output/qa_post_compile/audit_report
# -----------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

parse_named_args <- function(args) {
  values <- list()
  if (!length(args)) return(values)
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }
  values
}

wilson_ci <- function(x, n, z = 1.96) {
  if (is.na(n) || n == 0L) return(list(center = NA_real_, lower = NA_real_, upper = NA_real_))
  p_hat  <- x / n
  z2n    <- z^2 / n
  center <- (p_hat + z2n / 2) / (1 + z2n)
  margin <- z * sqrt(p_hat * (1 - p_hat) / n + z^2 / (4 * n^2)) / (1 + z2n)
  list(center = center, lower = max(0, center - margin), upper = min(1, center + margin))
}

make_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

write_csv_out <- function(df, path) {
  write.csv(df, path, row.names = FALSE)
}

empty_accuracy_row <- function(by_col, by_val) {
  row <- list(n_reviewed = 0L, n_correct = 0L, n_partially_correct = 0L,
              n_incorrect = 0L, n_unverifiable = 0L,
              accuracy_pct = NA_real_, accuracy_ci_lower = NA_real_, accuracy_ci_upper = NA_real_)
  setNames(c(list(by_val), row), c(by_col, names(row)))
}

accuracy_table_by <- function(df, by_col) {
  raw_levels <- unique(df[[by_col]])
  n_na <- sum(is.na(raw_levels))
  if (n_na > 0L) {
    warning(sprintf("%d row(s) with NA %s excluded from accuracy table.", n_na, by_col))
  }
  levels <- sort(raw_levels[!is.na(raw_levels)])
  rows <- lapply(levels, function(val) {
    sub_df <- df[df[[by_col]] == val, ]
    n      <- nrow(sub_df)
    nc     <- sum(sub_df$final_label == "correct",           na.rm = TRUE)
    npc    <- sum(sub_df$final_label == "partially_correct", na.rm = TRUE)
    ni     <- sum(sub_df$final_label == "incorrect",         na.rm = TRUE)
    nu     <- sum(sub_df$final_label == "unverifiable",      na.rm = TRUE)
    ci     <- wilson_ci(nc, n)
    data.frame(
      by_col_placeholder = val,
      n_reviewed          = n,
      n_correct           = nc,
      n_partially_correct = npc,
      n_incorrect         = ni,
      n_unverifiable      = nu,
      accuracy_pct        = round(ci$center * 100, 2),
      accuracy_ci_lower   = round(ci$lower  * 100, 2),
      accuracy_ci_upper   = round(ci$upper  * 100, 2),
      stringsAsFactors    = FALSE
    )
  })
  out <- do.call(rbind, rows)
  if (!is.null(out)) names(out)[1] <- by_col
  out
}

# ---------------------------------------------------------------------------
# Parse CLI args
# ---------------------------------------------------------------------------
args       <- parse_named_args(commandArgs(trailingOnly = TRUE))
input_path <- args$input %||% "DryadPlantTraits/output/qa_post_compile/publication_audit_sample.csv"
output_dir <- args[["output-dir"]] %||% args$output_dir %||%
              "DryadPlantTraits/output/qa_post_compile/audit_report"

make_dir(output_dir)

# ---------------------------------------------------------------------------
# Step 1 — Read audit sample
# ---------------------------------------------------------------------------
message("Reading audit sample: ", input_path)
if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, call. = FALSE)
}
audit <- read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE, na.strings = "")

required_cols <- c("reviewer_1_label", "reviewer_2_label",
                   "adjudicator_label", "trait_name", "dryad_dataset_doi")
missing <- setdiff(required_cols, names(audit))
if (length(missing)) {
  stop("Input CSV is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
}

# ---------------------------------------------------------------------------
# Step 2 — Filter to filled rows
# ---------------------------------------------------------------------------
message("Filtering to rows with both reviewer labels filled...")
filled <- audit[
  !is.na(audit$reviewer_1_label) & nzchar(trimws(audit$reviewer_1_label)) &
  !is.na(audit$reviewer_2_label) & nzchar(trimws(audit$reviewer_2_label)),
]
n_filled <- nrow(filled)
message("  Filled rows: ", n_filled, " of ", nrow(audit))

if (n_filled == 0L) {
  warning("No filled reviewer rows found — writing empty reports and exiting.")
  empty_summary <- data.frame(
    n_filled = 0L, n_agreed = NA_integer_,
    agreement_pct = NA_real_, agreement_ci_lower = NA_real_, agreement_ci_upper = NA_real_,
    n_adjudicated = NA_integer_,
    accuracy_pct = NA_real_, accuracy_ci_lower = NA_real_, accuracy_ci_upper = NA_real_
  )
  write_csv_out(empty_summary,       file.path(output_dir, "audit_report_summary.csv"))
  write_csv_out(data.frame(),        file.path(output_dir, "trait_accuracy_table.csv"))
  write_csv_out(data.frame(),        file.path(output_dir, "dataset_accuracy_table.csv"))
  write_csv_out(data.frame(),        file.path(output_dir, "error_type_frequency.csv"))
  write_csv_out(data.frame(),        file.path(output_dir, "reviewer_confusion_matrix.csv"))
  write_csv_out(data.frame(),        file.path(output_dir, "rows_needs_adjudication.csv"))
  cat("AUDIT_REPORT_COMPLETE\n")
  cat("n_filled=0\n")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# Step 3 — Reviewer agreement
# ---------------------------------------------------------------------------
message("Computing inter-rater agreement...")
filled$agreed <- trimws(filled$reviewer_1_label) == trimws(filled$reviewer_2_label)
n_agreed      <- sum(filled$agreed, na.rm = TRUE)
agree_ci      <- wilson_ci(n_agreed, n_filled)

# ---------------------------------------------------------------------------
# Step 4 — Adjudicate final labels
# ---------------------------------------------------------------------------
message("Resolving adjudicated labels...")
filled$final_label <- NA_character_

adj_raw <- filled$adjudicator_label
has_adj  <- !is.na(adj_raw) & nzchar(trimws(ifelse(is.na(adj_raw), "", adj_raw)))
filled$final_label <- ifelse(
  has_adj,
  trimws(adj_raw),
  ifelse(
    filled$agreed,
    trimws(filled$reviewer_1_label),
    "needs_adjudication"
  )
)

adjudicated  <- filled[filled$final_label != "needs_adjudication", ]
needs_adj    <- filled[filled$final_label == "needs_adjudication", ]
n_adjudicated <- nrow(adjudicated)

n_correct    <- sum(adjudicated$final_label == "correct", na.rm = TRUE)
accuracy_ci  <- wilson_ci(n_correct, n_adjudicated)

# ---------------------------------------------------------------------------
# Step 5 — Trait-level accuracy table
# ---------------------------------------------------------------------------
message("Building trait-level accuracy table...")
trait_tbl <- if (n_adjudicated > 0L) {
  accuracy_table_by(adjudicated, "trait_name")
} else {
  data.frame()
}

# ---------------------------------------------------------------------------
# Step 6 — Dataset-level accuracy table
# ---------------------------------------------------------------------------
message("Building dataset-level accuracy table...")
dataset_tbl <- if (n_adjudicated > 0L) {
  accuracy_table_by(adjudicated, "dryad_dataset_doi")
} else {
  data.frame()
}

# ---------------------------------------------------------------------------
# Step 7 — Error type frequency table
# ---------------------------------------------------------------------------
message("Tabulating error type frequencies...")
label_counts <- as.data.frame(table(final_label = filled$final_label), stringsAsFactors = FALSE)
names(label_counts)[2] <- "n"

# ---------------------------------------------------------------------------
# Step 8 — Reviewer confusion matrix
# ---------------------------------------------------------------------------
message("Building reviewer confusion matrix...")
r1_levels <- sort(unique(trimws(filled$reviewer_1_label)))
r2_levels <- sort(unique(trimws(filled$reviewer_2_label)))
confusion  <- table(
  reviewer_1 = factor(trimws(filled$reviewer_1_label), levels = r1_levels),
  reviewer_2 = factor(trimws(filled$reviewer_2_label), levels = r2_levels)
)
confusion_df <- as.data.frame.matrix(confusion)
confusion_df <- cbind(reviewer_1_label = rownames(confusion_df), confusion_df)
rownames(confusion_df) <- NULL

# ---------------------------------------------------------------------------
# Step 9 — Write outputs
# ---------------------------------------------------------------------------
message("Writing outputs to: ", output_dir)

summary_row <- data.frame(
  n_filled           = n_filled,
  n_agreed           = n_agreed,
  agreement_pct      = round(agree_ci$center * 100, 2),
  agreement_ci_lower = round(agree_ci$lower  * 100, 2),
  agreement_ci_upper = round(agree_ci$upper  * 100, 2),
  n_adjudicated      = n_adjudicated,
  accuracy_pct       = round(accuracy_ci$center * 100, 2),
  accuracy_ci_lower  = round(accuracy_ci$lower  * 100, 2),
  accuracy_ci_upper  = round(accuracy_ci$upper  * 100, 2),
  stringsAsFactors   = FALSE
)

write_csv_out(summary_row,   file.path(output_dir, "audit_report_summary.csv"))
write_csv_out(trait_tbl,     file.path(output_dir, "trait_accuracy_table.csv"))
write_csv_out(dataset_tbl,   file.path(output_dir, "dataset_accuracy_table.csv"))
write_csv_out(label_counts,  file.path(output_dir, "error_type_frequency.csv"))
write_csv_out(confusion_df,  file.path(output_dir, "reviewer_confusion_matrix.csv"))
write_csv_out(needs_adj,     file.path(output_dir, "rows_needs_adjudication.csv"))

# ---------------------------------------------------------------------------
# Step 10 — Summary to stdout
# ---------------------------------------------------------------------------
cat("AUDIT_REPORT_COMPLETE\n")
cat("n_filled=",           n_filled,                              "\n", sep = "")
cat("n_agreed=",           n_agreed,                              "\n", sep = "")
cat("agreement_pct=",      round(agree_ci$center * 100, 2),      "\n", sep = "")
cat("agreement_ci=",       round(agree_ci$lower  * 100, 2), "-",
                           round(agree_ci$upper  * 100, 2),      "\n", sep = "")
cat("n_adjudicated=",      n_adjudicated,                         "\n", sep = "")
cat("accuracy_pct=",       round(accuracy_ci$center * 100, 2),   "\n", sep = "")
cat("accuracy_ci=",        round(accuracy_ci$lower  * 100, 2), "-",
                           round(accuracy_ci$upper  * 100, 2),   "\n", sep = "")
cat("needs_adjudication=", nrow(needs_adj),                       "\n", sep = "")
