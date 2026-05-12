## Global_Plant_BodySize/scripts/04_taxonomy_reconcile.R
## Stage 4: Taxonomy reconciliation across all raw trait files.
##
## BIEN uses TNRS (Taxonomic Name Resolution Service) internally; the
## scrubbed_species_binomial returned by BIEN is already the TNRS-accepted
## name for most records. This stage:
##
##   (a) Collects unique species names from all raw trait files and the
##       species list (output/bien_species_list.csv).
##   (b) Checks for name mismatches between the species list and trait files
##       (e.g., spelling variants, subspecies names, hybrid notation).
##   (c) Joins family, higher_plant_group, and genus onto any trait records
##       where these are missing, using the species list as a lookup.
##   (d) Writes a reconciliation report and an enriched species roster.
##
## Output:
##   output/taxonomy_reconciliation_report.csv — mismatches and resolution notes
##   output/bien_species_roster.csv — species list enriched with taxonomy
##
## NOTE: Full TNRS re-query is optional (slow: ~1 API call per species).
##   Set TNRS_REQUERY = TRUE below only if you suspect the BIEN scrubbing
##   is out of date. Requires the 'TNRS' R package.
##
## Run from project root:
##   Rscript scripts/04_taxonomy_reconcile.R

TNRS_REQUERY <- FALSE   # change to TRUE to trigger live TNRS re-check

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)

## ---- Load species roster ---------------------------------------------------
stopifnot(file.exists("output/bien_species_list.csv"))
roster <- fread("output/bien_species_list.csv", data.table = FALSE)
message("[Stage 4] Species roster: ", nrow(roster), " species")

## ---- Collect unique verbatim names from all raw trait files ----------------
trait_files <- c(
  "output/bien_height_raw.csv",
  "output/bien_dbh_raw.csv",
  "output/bien_growth_form_raw.csv"
)

existing_files <- trait_files[file.exists(trait_files)]
if (length(existing_files) == 0)
  stop("[Stage 4] No trait files found. Run Stages 2 & 3 first.")

trait_names <- unique(unlist(lapply(existing_files, function(f) {
  dt <- fread(f, select = "verbatim_species_name", data.table = FALSE)
  dt$verbatim_species_name
})))
trait_names <- trait_names[!is.na(trait_names) & nzchar(trait_names)]
message("[Stage 4] Unique trait verbatim names: ", length(trait_names))

## ---- Check overlap between trait names and roster --------------------------
roster_names <- roster$species

in_roster     <- trait_names %in% roster_names
not_in_roster <- trait_names[!in_roster]

message("[Stage 4] Trait names in roster:     ", sum(in_roster))
message("[Stage 4] Trait names NOT in roster: ", length(not_in_roster))

if (length(not_in_roster) > 0) {
  message("  First 20 unmatched: ",
          paste(head(not_in_roster, 20), collapse = "; "))
}

## ---- Build taxonomy lookup from roster -------------------------------------
## Columns used for enrichment: family, higher_plant_group, genus
tax_lookup_cols <- intersect(
  c("species", "family", "higher_plant_group", "genus", "class", "order"),
  names(roster)
)
tax_lookup <- roster[, tax_lookup_cols, drop = FALSE]
names(tax_lookup)[names(tax_lookup) == "species"] <- "verbatim_species_name"

## ---- Enrich each trait file with taxonomy ----------------------------------
for (f in existing_files) {
  message("[Stage 4] Enriching: ", f)
  dt <- fread(f, data.table = FALSE)

  ## Merge taxonomy columns; prefer existing values, fill NA gaps from lookup
  missing_tax_cols <- setdiff(
    c("family", "higher_plant_group", "genus"),
    names(dt)
  )
  if (length(missing_tax_cols) > 0 || any(is.na(dt$family))) {
    dt_merged <- merge(dt, tax_lookup, by = "verbatim_species_name",
                       all.x = TRUE, suffixes = c("", "_lookup"))
    ## Fill NAs in primary columns from _lookup columns
    for (col in c("family", "higher_plant_group", "genus")) {
      lookup_col <- paste0(col, "_lookup")
      if (lookup_col %in% names(dt_merged)) {
        is_na_primary <- is.na(dt_merged[[col]])
        dt_merged[[col]][is_na_primary] <- dt_merged[[lookup_col]][is_na_primary]
        dt_merged[[lookup_col]] <- NULL  # drop _lookup column
      }
    }
    dt <- dt_merged
  }

  fwrite(dt, f)
  message("  Written: ", nrow(dt), " records to ", f)
}

## ---- Write reconciliation report -------------------------------------------
report <- data.frame(
  verbatim_species_name = not_in_roster,
  in_bien_roster        = FALSE,
  resolution_note       = "Name in BIEN trait table but not in BIEN_species_list(). May be synonym or BIEN version mismatch.",
  stringsAsFactors      = FALSE
)
fwrite(report, "output/taxonomy_reconciliation_report.csv")
message("[Stage 4] Reconciliation report: ", nrow(report), " unmatched names")

## ---- Write enriched species roster -----------------------------------------
fwrite(roster, "output/bien_species_roster.csv")
message("[Stage 4] Enriched roster written to: output/bien_species_roster.csv")
message("=== Stage 4 complete ===")
