#!/usr/bin/env Rscript
# build_taxon_lists.R
# Pre-compute BIEN taxon lists (species/genus/family) for autocomplete.
# Outputs three RDS files into BIEN-TraitsShinyApp/data/ that get bundled
# with the deploy. The Shiny app reads these at startup; live BIEN SQL is
# only used as a fallback. This eliminates runtime LIMIT truncation,
# transient SQL failures, and silent demotion to a tiny hardcoded list.
#
# Run locally with valid BIEN DB access:
#   Rscript BIEN-TraitsShinyApp/tools/build_taxon_lists.R
#
# Refresh policy: re-run when BIEN taxonomy is updated (a few times per
# year is plenty). The accompanying built_on.txt file records the snapshot
# date for transparency.

suppressPackageStartupMessages({
  library(BIEN)
})

out_dir <- normalizePath(file.path("BIEN-TraitsShinyApp", "data"), mustWork = FALSE)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

bien_sql <- get(".BIEN_sql", envir = asNamespace("BIEN"))

# Pull all rows we plausibly want for autocomplete. We deliberately do NOT
# restrict to scrubbed_taxonomic_status = 'Accepted' here, because some
# valid genera (e.g. Xylosma) are absent from the Accepted-only result set
# in the current BIEN taxonomy snapshot. Including non-accepted rows means
# users can find any name BIEN knows about; downstream BIEN_trait_*
# functions still apply their own taxonomic standardization.
fetch <- function(col, where_extra = "") {
  sql <- sprintf(
    "SELECT DISTINCT %s AS taxon FROM bien_taxonomy WHERE %s IS NOT NULL AND %s <> '' %s ORDER BY 1;",
    col, col, col, where_extra
  )
  cat("Querying:", col, "...\n")
  res <- bien_sql(query = sql, fetch.query = FALSE)
  vals <- unique(as.character(res$taxon))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  cat("  rows:", length(vals), "\n")
  vals
}

species_vals <- fetch("scrubbed_species_binomial")
genus_vals   <- fetch("scrubbed_genus")
family_vals  <- fetch("scrubbed_family")

# Sanity check: a few late-alphabet markers we know should exist.
markers <- c("Xylosma", "Yucca", "Zanthoxylum")
present <- markers[markers %in% genus_vals]
cat("Late-alphabet genus markers present:", paste(present, collapse = ", "), "\n")
missing <- setdiff(markers, present)
if (length(missing) > 0) {
  warning("Missing expected genera: ", paste(missing, collapse = ", "))
}

saveRDS(species_vals, file.path(out_dir, "taxon_species.rds"))
saveRDS(genus_vals,   file.path(out_dir, "taxon_genus.rds"))
saveRDS(family_vals,  file.path(out_dir, "taxon_family.rds"))

writeLines(
  c(
    paste0("built_on: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("species_n: ", length(species_vals)),
    paste0("genus_n: ",   length(genus_vals)),
    paste0("family_n: ",  length(family_vals)),
    paste0("source: bien_taxonomy (no Accepted filter; full DISTINCT)"),
    paste0("script: tools/build_taxon_lists.R")
  ),
  file.path(out_dir, "taxon_lists_built_on.txt")
)

cat("Wrote RDS to:", out_dir, "\n")
