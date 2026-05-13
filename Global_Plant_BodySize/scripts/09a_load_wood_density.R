## Global_Plant_BodySize/scripts/09a_load_wood_density.R
## Stage 9a: Download and join Global Wood Density Database (GWDD) to species roster.
##
## Source:
##   Zanne AE, Lopez-Gonzalez G, Coomes DA, Ilic J, Jansen S, Lewis SL,
##   Miller RB, Swenson NG, Wiemann MC, Chave J. 2009.
##   Data from: Towards a worldwide wood economics spectrum.
##   Dryad Digital Repository. https://doi.org/10.5061/dryad.234
##
##   Chave J, Coomes DA, Jansen S, Lewis SL, Swenson NG, Zanne AE. 2009.
##   Towards a worldwide wood economics spectrum.
##   Ecology Letters 12(4):351–366. https://doi.org/10.1111/j.1461-0248.2009.01285.x
##
## NOTE: DOIs above are taken from published literature and require independent
##       verification before use in any publication.
##
## Match hierarchy (species → genus → family → angiosperm/gymnosperm fallback):
##   Level 1 (species):     exact binomial match in GWDD
##   Level 2 (genus):       mean rho across all congeneric species in GWDD
##   Level 3 (family):      mean rho across all confamilial species in GWDD
##   Level 4 (angiosperm):  global angiosperm mean from GWDD (0.58 g/cm³ approx)
##   Level 5 (gymnosperm):  global gymnosperm mean from GWDD (0.48 g/cm³ approx)
##   Level 6 (none):        NA — non-woody taxa (herbs, graminoids, aquatics)
##
## Non-woody growth forms receive rho_mean = NA; biomass for these species is
## estimated in Stage 9b using growth-form-specific equations that do not
## require wood density.
##
## Output:
##   output/species_wood_density.csv — one row per species with:
##     species_name, rho_mean, rho_sd, rho_n, rho_match_level, rho_source
##
## Run from project root:
##   Rscript scripts/09a_load_wood_density.R
##   Rscript scripts/09a_load_wood_density.R --overwrite

args      <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))
if (!requireNamespace("BIOMASS", quietly = TRUE)) {
  stop("[Stage 9a] R package 'BIOMASS' is required. Install with: install.packages('BIOMASS')")
}

## ---- Constants --------------------------------------------------------------

## Fallback: hardcoded global means from Chave et al. 2014 Supplementary Table 2
## (flagged UNVERIFIED — verify before publication)
ANGIOSPERM_FALLBACK_RHO  <- 0.58   ## g/cm³ — UNVERIFIED
ANGIOSPERM_FALLBACK_SD   <- 0.18   ## UNVERIFIED

OUTPUT_FILE <- "output/species_wood_density.csv"

## Woody growth forms — only these get wood density lookups
WOODY_GROWTH_FORMS <- c("tree", "shrub", "subshrub", "bamboo", "vine", "epiphyte")

## ---- Load GWDD from BIOMASS package ----------------------------------------
## BIOMASS::wdData contains the Zanne et al. 2009 GWDD.
## Columns: family, genus, species (epithet only), wd, region, referenceNumber, regionId
##   - 'wd' is wood density in g/cm³
##   - 'species' is the epithet only; binomial = paste(genus, species)

e <- new.env()
data("wdData", package = "BIOMASS", envir = e)
gwdd_raw <- as.data.table(e$wdData)

message("[Stage 9a] GWDD loaded from BIOMASS::wdData: ", nrow(gwdd_raw), " rows")
message("[Stage 9a] Columns: ", paste(names(gwdd_raw), collapse = ", "))

## Build binomial, clean up
gwdd <- data.table(
  gwdd_binomial = trimws(paste(gwdd_raw$genus, gwdd_raw$species)),
  gwdd_genus    = trimws(as.character(gwdd_raw$genus)),
  gwdd_family   = trimws(as.character(gwdd_raw$family)),
  rho_raw       = suppressWarnings(as.numeric(gwdd_raw$wd))
)

## Remove rows with NA rho or empty names
gwdd <- gwdd[!is.na(rho_raw) & nzchar(gwdd_binomial) & gwdd_binomial != "NA NA"]
message("[Stage 9a] GWDD usable rows (rho non-NA): ", nrow(gwdd))
message("[Stage 9a] Unique species: ", uniqueN(gwdd$gwdd_binomial))
message("[Stage 9a] Unique genera:  ", uniqueN(gwdd$gwdd_genus))
message("[Stage 9a] Unique families: ", uniqueN(gwdd$gwdd_family))

## ---- Build aggregates for hierarchical matching ----------------------------
## Level 1: species means (some GWDD entries have multiple regional measurements)
sp_means <- gwdd[, .(rho_mean = mean(rho_raw, na.rm = TRUE),
                     rho_sd   = sd(rho_raw,   na.rm = TRUE),
                     rho_n    = .N),
                 by = gwdd_binomial]
sp_means[is.na(rho_sd), rho_sd := 0]

## Level 2: genus means
genus_means <- gwdd[, .(rho_mean = mean(rho_raw, na.rm = TRUE),
                        rho_sd   = sd(rho_raw,   na.rm = TRUE),
                        rho_n    = .N),
                    by = gwdd_genus]
genus_means[is.na(rho_sd), rho_sd := 0]

## Level 3: family means
family_means <- gwdd[!is.na(gwdd_family) & nzchar(gwdd_family),
                     .(rho_mean = mean(rho_raw, na.rm = TRUE),
                       rho_sd   = sd(rho_raw,   na.rm = TRUE),
                       rho_n    = .N),
                     by = gwdd_family]
family_means[is.na(rho_sd), rho_sd := 0]

## ---- Load species list with taxonomy from final database -------------------
stopifnot(file.exists("output/plant_bodysize_final.csv"))

spp <- fread("output/plant_bodysize_final.csv",
             select = c("species_name", "family", "genus",
                        "growth_form_canonical"),
             data.table = TRUE)
## Coerce family/genus to plain character (may be list-col if any JSON in CSV)
spp[, family := as.character(family)]
spp[, genus  := as.character(genus)]
message("[Stage 9a] Species loaded: ", nrow(spp))

## Identify woody species (only they get wood density)
spp[, is_woody := growth_form_canonical %in% WOODY_GROWTH_FORMS]
message("[Stage 9a] Woody species: ", sum(spp$is_woody, na.rm = TRUE))

## Extract genus from species name for matching if genus column is sparse
spp[is.na(genus) | !nzchar(genus), genus := sub(" .*", "", species_name)]

## ---- Hierarchical wood density matching ------------------------------------
result <- copy(spp[, .(species_name, family, genus, growth_form_canonical, is_woody)])
result[, c("rho_mean", "rho_sd", "rho_n", "rho_match_level") :=
         .(NA_real_, NA_real_, NA_integer_, NA_character_)]

## For non-woody species: set match_level = "none" explicitly
result[is_woody == FALSE | is.na(is_woody),
       rho_match_level := "none"]

woody_idx <- which(result$is_woody == TRUE)
message("[Stage 9a] Matching wood density for ", length(woody_idx), " woody species...")

## Level 1: species-level match
l1 <- merge(
  result[woody_idx, .(species_name)],
  sp_means,
  by.x = "species_name", by.y = "gwdd_binomial",
  all.x = TRUE
)
result[woody_idx, c("rho_mean", "rho_sd", "rho_n", "rho_match_level") := {
  idx <- match(species_name, l1$species_name)
  list(
    ifelse(!is.na(l1$rho_mean[idx]), l1$rho_mean[idx], rho_mean),
    ifelse(!is.na(l1$rho_mean[idx]), l1$rho_sd[idx],   rho_sd),
    ifelse(!is.na(l1$rho_mean[idx]), l1$rho_n[idx],    rho_n),
    ifelse(!is.na(l1$rho_mean[idx]), "species",         rho_match_level)
  )
}]

## Level 2: genus-level match for unmatched woody species
still_unmatched_woody <- result[is_woody == TRUE & is.na(rho_mean)]
if (nrow(still_unmatched_woody) > 0) {
  l2 <- merge(
    still_unmatched_woody[, .(species_name, genus)],
    genus_means,
    by.x = "genus", by.y = "gwdd_genus",
    all.x = TRUE
  )
  result[species_name %in% l2$species_name & is.na(rho_mean),
         c("rho_mean", "rho_sd", "rho_n", "rho_match_level") := {
           idx <- match(species_name, l2$species_name)
           list(
             ifelse(!is.na(l2$rho_mean[idx]), l2$rho_mean[idx], rho_mean),
             ifelse(!is.na(l2$rho_mean[idx]), l2$rho_sd[idx],   rho_sd),
             ifelse(!is.na(l2$rho_mean[idx]), l2$rho_n[idx],    rho_n),
             ifelse(!is.na(l2$rho_mean[idx]), "genus",           rho_match_level)
           )
         }]
}

## Level 3: family-level match
still_unmatched_woody <- result[is_woody == TRUE & is.na(rho_mean)]
if (nrow(still_unmatched_woody) > 0) {
  l3 <- merge(
    still_unmatched_woody[, .(species_name, family)],
    family_means,
    by.x = "family", by.y = "gwdd_family",
    all.x = TRUE
  )
  result[species_name %in% l3$species_name & is.na(rho_mean),
         c("rho_mean", "rho_sd", "rho_n", "rho_match_level") := {
           idx <- match(species_name, l3$species_name)
           list(
             ifelse(!is.na(l3$rho_mean[idx]), l3$rho_mean[idx], rho_mean),
             ifelse(!is.na(l3$rho_mean[idx]), l3$rho_sd[idx],   rho_sd),
             ifelse(!is.na(l3$rho_mean[idx]), l3$rho_n[idx],    rho_n),
             ifelse(!is.na(l3$rho_mean[idx]), "family",          rho_match_level)
           )
         }]
}

## Level 4/5: angiosperm/gymnosperm fallback for still-unmatched woody species
## (We use a single angiosperm fallback here since BIEN is mostly angiosperms;
##  gymnosperm flag would require higher_plant_group = "Gymnosperm" column.)
still_unmatched_woody <- result[is_woody == TRUE & is.na(rho_mean)]
if (nrow(still_unmatched_woody) > 0) {
  result[is_woody == TRUE & is.na(rho_mean),
         c("rho_mean", "rho_sd", "rho_n", "rho_match_level") :=
           .(ANGIOSPERM_FALLBACK_RHO, ANGIOSPERM_FALLBACK_SD, 0L, "global_fallback")]
}

## Add metadata
result[, rho_source := "GWDD_Zanne2009"]
result[rho_match_level == "none",     rho_source := NA_character_]
result[rho_match_level == "global_fallback",
       rho_source := "GWDD_Zanne2009_global_fallback_UNVERIFIED"]

## Drop helper columns
result[, is_woody := NULL]

## ---- Report ----------------------------------------------------------------
tab <- table(result$rho_match_level, useNA = "ifany")
message("[Stage 9a] Wood density match summary:")
for (nm in names(tab)) message("  ", nm, ": ", tab[[nm]])

## ---- Write output ----------------------------------------------------------
dir.create("output", showWarnings = FALSE)
fwrite(result, OUTPUT_FILE)
message("[Stage 9a] Wood density table written: ", OUTPUT_FILE,
        " (", nrow(result), " rows)")
message("=== Stage 9a complete ===")
