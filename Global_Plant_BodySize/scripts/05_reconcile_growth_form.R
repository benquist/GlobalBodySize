## Global_Plant_BodySize/scripts/05_reconcile_growth_form.R
## Stage 5: Reconcile BIEN growth form strings to canonical vocabulary and
## apply special group flags (graminoid, bamboo, bryophyte).
##
## Input:  output/bien_growth_form_raw.csv
## Output: output/bien_growth_form_reconciled.csv — one row per observation
##         output/species_growth_form.csv — one row per species (modal growth form)
##
## Logic:
##   1. Map BIEN freetext growth form → canonical using map_bien_growth_form()
##   2. Apply family-based override: Poaceae/Cyperaceae/Juncaceae → graminoid
##   3. Apply bamboo sub-flag: Bambusoideae subfamily OR genus in bamboo list → bamboo
##   4. Per species: take modal canonical growth form (most frequent)
##      If tie, prefer the more specific category (bamboo > graminoid > tree > shrub)
##      Flag species with conflicting records (growth_form_conflict = TRUE)
##   5. Bryophyte flag: always FALSE for BIEN species (documented explicitly)
##
## NOTE on bamboo: BIEN does not consistently return subfamily information.
## The genus-based flag (plantsize_bamboo_genera()) is the primary bamboo
## detection method for BIEN data. Confirm bamboo assignments for key genera
## (Chusquea, Guadua) before publication.
##
## Run from project root:
##   Rscript scripts/05_reconcile_growth_form.R

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)
source("R/growth_form_vocab.R")   # also sources plant_size_schema.R

## ---- Load raw growth form data ---------------------------------------------
gf_file <- "output/bien_growth_form_raw.csv"
stopifnot(file.exists(gf_file))

gf <- fread(gf_file, data.table = FALSE)
message("[Stage 5] Growth form records loaded: ", nrow(gf))

## ---- Map BIEN freetext → canonical -----------------------------------------
gf$canonical_mapped <- map_bien_growth_form(gf$trait_value_verbatim)

## ---- Apply family-based graminoid override ---------------------------------
gf$is_graminoid <- flag_graminoid(gf$family)

## ---- Apply bamboo flag (genus-based; subfamily supplementary if available) --
gf$is_bamboo <- flag_bamboo(
  genus_vec     = gf$genus,
  subfamily_vec = if ("subfamily" %in% names(gf)) gf$subfamily else NULL
)

## ---- Resolve final canonical growth form with family/bamboo override --------
gf$growth_form_canonical <- resolve_canonical_growth_form(
  mapped_growth_form = gf$canonical_mapped,
  family_vec         = gf$family,
  genus_vec          = gf$genus,
  subfamily_vec      = if ("subfamily" %in% names(gf)) gf$subfamily else NULL
)

## ---- Explicit bryophyte flag (always FALSE for BIEN) -----------------------
gf$is_bryophyte <- FALSE
## Rationale: BIEN covers vascular plants only. If non-vascular taxa are added
## from other sources in a future stage, this flag will identify them.

## ---- Write reconciled raw table --------------------------------------------
fwrite(gf, "output/bien_growth_form_reconciled.csv")
message("[Stage 5] Reconciled growth form written: ", nrow(gf), " records")

## ---- Collapse to species-level modal growth form ---------------------------
## Priority order for tie-breaking: bamboo > graminoid > tree > shrub > herb > vine > other
priority_order <- c("bamboo", "graminoid", "tree", "shrub", "subshrub",
                    "herb", "vine", "epiphyte", "aquatic", "parasite", "unknown")

species_gf <- do.call(rbind, lapply(split(gf, gf$verbatim_species_name), function(df) {
  ## Count each canonical value
  tbl     <- sort(table(df$growth_form_canonical), decreasing = TRUE)
  top_val <- names(tbl)[1]
  n_rec   <- nrow(df)
  n_unique <- length(unique(df$growth_form_canonical[
    df$growth_form_canonical != "unknown"
  ]))

  ## Tie-break using priority order if multiple values have the same count
  top_count <- tbl[1]
  tied_vals <- names(tbl[tbl == top_count])
  if (length(tied_vals) > 1) {
    priority_match <- priority_order[priority_order %in% tied_vals]
    top_val <- if (length(priority_match) > 0) priority_match[1] else tied_vals[1]
  }

  data.frame(
    species_name           = df$verbatim_species_name[1],
    family                 = df$family[1],
    genus                  = df$genus[1],
    higher_plant_group     = df$higher_plant_group[1],
    subfamily              = if ("subfamily" %in% names(df)) df$subfamily[1] else NA_character_,
    growth_form_canonical  = top_val,
    growth_form_n_records  = n_rec,
    growth_form_conflict   = n_unique > 1,
    is_graminoid           = any(df$is_graminoid),
    is_bamboo              = any(df$is_bamboo),
    is_bryophyte           = FALSE,
    stringsAsFactors       = FALSE
  )
}))

rownames(species_gf) <- NULL

## ---- Report -----------------------------------------------------------------
message("[Stage 5] Species with growth form data: ", nrow(species_gf))
message("[Stage 5] Growth form distribution:")
print(sort(table(species_gf$growth_form_canonical), decreasing = TRUE))
message("[Stage 5] Species with conflicting growth forms: ",
        sum(species_gf$growth_form_conflict))
message("[Stage 5] Graminoid species: ", sum(species_gf$is_graminoid))
message("[Stage 5] Bamboo species:    ", sum(species_gf$is_bamboo))

fwrite(species_gf, "output/species_growth_form.csv")
message("[Stage 5] Species growth form table: output/species_growth_form.csv")
message("=== Stage 5 complete ===")
