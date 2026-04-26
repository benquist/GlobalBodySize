#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

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

parse_required_integer_arg <- function(raw_value, arg_name, min_value = NULL) {
  txt <- trimws(as.character(if (is.null(raw_value) || !length(raw_value)) "" else raw_value))
  if (!nzchar(txt)) {
    stop("Missing required --", arg_name, " argument.", call. = FALSE)
  }
  if (!grepl("^-?[0-9]+$", txt)) {
    stop("Invalid --", arg_name, " value: '", txt, "'. Must be an integer.", call. = FALSE)
  }
  value <- suppressWarnings(as.integer(txt))
  if (is.na(value)) {
    stop("Invalid --", arg_name, " value: '", txt, "'. Must be an integer in 32-bit range.", call. = FALSE)
  }
  if (!is.null(min_value) && value < min_value) {
    stop("Invalid --", arg_name, " value: ", value, ". Must be >= ", min_value, ".", call. = FALSE)
  }
  value
}

parse_bool_arg <- function(raw_value, arg_name, default = FALSE) {
  if (is.null(raw_value)) return(default)
  txt <- tolower(trimws(as.character(raw_value)))
  if (txt %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (txt %in% c("false", "f", "0", "no", "n")) return(FALSE)
  stop("Invalid --", arg_name, " value: '", raw_value, "'. Use TRUE or FALSE.", call. = FALSE)
}

drop_model_columns <- function(df) {
  model_col_patterns <- c(
    "^qa_",
    "^dict_",
    "^range_(min_ref|max_ref|source_ref|reference_available|distance_abs|distance_rel|position)$",
    "^invalid_reference_range$",
    "^is_numeric_trait$",
    "^value_numeric$",
    "^value_numeric_parse_ok$",
    "^value_used_for_range_check$",
    "^unit_(conversion_applied|conversion_reason|match_standard|mismatch_no_conversion|standard)$",
    "^unit_original$",
    "^in_reference_range$"
  )
  model_col_regex <- paste(model_col_patterns, collapse = "|")
  keep_idx <- !grepl(model_col_regex, names(df))
  df[, keep_idx, drop = FALSE]
}

find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") return(dirname(cwd))
  proj <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(proj)) return(proj)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

stratified_sample_indices <- function(df, n, seed) {
  set.seed(seed)
  if (!nrow(df)) return(integer(0))

  key <- paste(df$qa_decision, df$trait_name, df$unit_conversion_applied, sep = "||")
  groups <- split(seq_len(nrow(df)), key)
  group_sizes <- vapply(groups, length, integer(1))
  g <- length(groups)

  if (n <= 0) return(integer(0))

  alloc <- rep(0L, g)
  if (n < g) {
    pick <- sample(seq_len(g), size = n, prob = group_sizes)
    alloc[pick] <- 1L
  } else {
    alloc[] <- 1L
    remaining <- n - g
    if (remaining > 0) {
      capacity <- pmax(group_sizes - 1L, 0L)
      while (remaining > 0 && sum(capacity) > 0) {
        probs <- capacity / sum(capacity)
        j <- sample(seq_len(g), size = 1, prob = probs)
        alloc[[j]] <- alloc[[j]] + 1L
        capacity[[j]] <- max(capacity[[j]] - 1L, 0L)
        remaining <- remaining - 1L
      }
    }
  }

  idx <- integer(0)
  for (i in seq_along(groups)) {
    k <- min(alloc[[i]], length(groups[[i]]))
    if (k > 0) {
      idx <- c(idx, sample(groups[[i]], size = k))
    }
  }

  idx
}

args <- parse_named_args(commandArgs(trailingOnly = TRUE))
root <- find_project_root()

input <- args$input %||% file.path(root, "output", "qa_post_compile", "observations_scored.csv")
n <- parse_required_integer_arg(args$n %||% "350", "n", min_value = 1L)
seed <- parse_required_integer_arg(args$seed %||% "20260426", "seed", min_value = 0L)
include_model_columns <- parse_bool_arg(args$`include-model-columns`, "include-model-columns", default = FALSE)
output <- args$output %||% file.path(root, "output", "qa_post_compile", "publication_audit_sample.csv")

if (!file.exists(input)) {
  stop("Input scored observations file not found: ", input, call. = FALSE)
}

scored <- utils::read.csv(input, stringsAsFactors = FALSE, check.names = FALSE)
if (!nrow(scored)) {
  stop("Input scored observations has zero rows: ", input, call. = FALSE)
}

needed <- c("qa_decision", "trait_name", "unit_conversion_applied")
missing <- setdiff(needed, names(scored))
if (length(missing)) {
  stop("Input is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
}

idx <- stratified_sample_indices(scored, n = min(n, nrow(scored)), seed = seed)
sample_df <- scored[idx, , drop = FALSE]

if (!include_model_columns) {
  sample_df <- drop_model_columns(sample_df)
}

sample_df$reviewer_1_label <- ""
sample_df$reviewer_1_notes <- ""
sample_df$reviewer_2_label <- ""
sample_df$reviewer_2_notes <- ""
sample_df$adjudicator_label <- ""
sample_df$adjudicator_notes <- ""
sample_df$source_publication_locator <- ""

out_dir <- dirname(output)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(sample_df, output, row.names = FALSE, na = "")

cat("PUBLICATION_AUDIT_SAMPLE_COMPLETE\n")
cat("sample_rows=", nrow(sample_df), "\n", sep = "")
cat("input_rows=", nrow(scored), "\n", sep = "")
cat("output=", output, "\n", sep = "")
