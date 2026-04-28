#!/usr/bin/env Rscript

parse_named_args <- function(args) {
  values <- list()
  if (!length(args)) return(values)
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key   <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }
  values
}

args     <- commandArgs(trailingOnly = TRUE)
cli      <- parse_named_args(args)

output_dir <- if (!is.null(cli[["output-dir"]])) cli[["output-dir"]] else "/tmp/dryadplanttraits_release"
repo       <- if (!is.null(cli[["repo"]]))        cli[["repo"]]        else "benquist/DataDryad"
dry_run    <- isTRUE(as.logical(cli[["dry-run"]]))

GH <- "/opt/homebrew/bin/gh"

suppressPackageStartupMessages(library(arrow))

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Input / output manifest
# ---------------------------------------------------------------------------
inputs <- list(
  list(
    src  = "DryadPlantTraits/output/compiled_trait_observations_with_unit_inference.csv",
    out  = file.path(output_dir, "dryadplanttraits_v1_full.parquet"),
    tag  = "v1-traits-full"
  ),
  list(
    src  = "DryadPlantTraits/output/qa_post_compile/observations_scored_with_dt.csv",
    out  = file.path(output_dir, "dryadplanttraits_v1_qa_scored.parquet"),
    tag  = "v1-traits-qa"
  ),
  list(
    src  = "DryadPlantTraits/output/qa_post_compile/observations_keep.csv",
    out  = file.path(output_dir, "dryadplanttraits_v1_qa_keep.parquet"),
    tag  = "v1-traits-qa"
  )
)

# CSV copy for casual users
keep_csv_src <- "DryadPlantTraits/output/qa_post_compile/observations_keep.csv"
keep_csv_dst <- file.path(output_dir, "dryadplanttraits_v1_qa_keep.csv")

# ---------------------------------------------------------------------------
# Step 1 — Convert CSVs to parquet
# ---------------------------------------------------------------------------
cat(sprintf("Output dir: %s\n", output_dir))
cat(sprintf("Dry-run: %s\n", dry_run))
cat(sprintf("Repo: %s\n\n", repo))

for (item in inputs) {
  cat(sprintf("[parquet] Reading %s ...\n", item$src))
  tbl <- arrow::read_csv_arrow(item$src)
  cat(sprintf("[parquet] Writing %s ...\n", item$out))
  arrow::write_parquet(
    tbl,
    item$out,
    compression       = "zstd",
    compression_level = 3L,
    chunk_size        = 131072L
  )
  sz <- file.info(item$out)$size
  cat(sprintf("[parquet] Wrote %s  (%.1f MB)\n\n", basename(item$out), sz / 1e6))
}

cat(sprintf("[csv-copy] Copying observations_keep.csv -> %s ...\n", keep_csv_dst))
file.copy(keep_csv_src, keep_csv_dst, overwrite = TRUE)
sz <- file.info(keep_csv_dst)$size
cat(sprintf("[csv-copy] Done (%.1f MB)\n\n", sz / 1e6))

if (dry_run) {
  cat("Dry-run mode: skipping GitHub release creation and uploads.\n")
  quit(save = "no", status = 0L)
}

# ---------------------------------------------------------------------------
# Step 2 — Create GitHub releases (one per tag)
# ---------------------------------------------------------------------------
releases <- list(
  list(
    tag   = "v1-traits-full",
    title = "DryadPlantTraits v1 \u2014 Full Compiled Traits + Unit Inference",
    notes = paste(
      "Full compiled plant trait observations from Dryad Digital Repository,",
      "with per-row unit inference via the DryadPlantTraits decision-tree pipeline.",
      "Single parquet file, zstd-compressed."
    )
  ),
  list(
    tag   = "v1-traits-qa",
    title = "DryadPlantTraits v1 \u2014 QA-Scored and Gold-Keep Subsets",
    notes = paste(
      "QA-scored trait observations (all rows with triage/scoring columns) plus",
      "the gold-keep subset that passed all QA gates.",
      "Parquet files (zstd) plus a plain CSV of the gold-keep subset for casual use."
    )
  )
)

gh_release_create <- function(tag, title, notes, repo) {
  result <- tryCatch({
    rc <- system2(
      GH,
      args   = c("release", "create", tag,
                 "--repo",       repo,
                 "--title",      title,
                 "--notes",      notes,
                 "--prerelease"),
      stdout = TRUE,
      stderr = TRUE
    )
    list(ok = TRUE, output = rc)
  }, error = function(e) {
    list(ok = FALSE, output = conditionMessage(e))
  })
  result
}

for (rel in releases) {
  cat(sprintf("[release] Creating release tag=%s ...\n", rel$tag))
  res <- gh_release_create(rel$tag, rel$title, rel$notes, repo)
  if (res$ok) {
    cat(sprintf("[release] Created: %s\n\n", paste(res$output, collapse = "\n")))
  } else {
    cat(sprintf("[release] Warning: create returned error (may already exist): %s\n\n",
                paste(res$output, collapse = " ")))
  }
}

# ---------------------------------------------------------------------------
# Step 3 — Upload files to their respective releases
# ---------------------------------------------------------------------------
upload_files <- c(
  inputs[[1]]$out,   # full parquet -> v1-traits-full
  inputs[[2]]$out,   # qa_scored parquet -> v1-traits-qa
  inputs[[3]]$out,   # qa_keep parquet -> v1-traits-qa
  keep_csv_dst       # qa_keep csv -> v1-traits-qa
)

upload_tags <- c(
  inputs[[1]]$tag,
  inputs[[2]]$tag,
  inputs[[3]]$tag,
  "v1-traits-qa"
)

for (i in seq_along(upload_files)) {
  fpath <- upload_files[[i]]
  tag   <- upload_tags[[i]]
  cat(sprintf("[upload] %s -> %s ...\n", basename(fpath), tag))
  rc <- system2(
    GH,
    args   = c("release", "upload", tag, fpath,
               "--repo",    repo,
               "--clobber"),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(rc, "status")
  if (is.null(status) || status == 0L) {
    cat(sprintf("[upload] OK: %s\n\n", basename(fpath)))
  } else {
    cat(sprintf("[upload] FAILED (exit %s): %s\n\n", status, paste(rc, collapse = " ")))
  }
}

cat("release_to_github.R complete.\n")
