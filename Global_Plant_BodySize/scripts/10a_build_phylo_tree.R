## Global_Plant_BodySize/scripts/10a_build_phylo_tree.R
## Stage 10a: Build phylogenetic tree for MEASURED species (Tiers 1-4)
##   using V.PhyloMaker2 with the Smith & Brown 2018 GBOTB backbone.
##
## BACKBONE: GBOTB.extended.WP (Global Backbone of the Tree of Biodiversity,
##   World Plants classification) — the V.PhyloMaker2 v0.1.0 equivalent of the
##   Smith & Brown 2018 GBMB backbone.
##   Smith SA & Brown JW (2018) Constructing a broadly inclusive seed plant
##   phylogeny. American Journal of Botany 105(3):302-314.
##   DOI: 10.3732/ajb.1700476  [VERIFIED]
##
##   NOTE: V.PhyloMaker2 v0.1.0 uses objects named GBOTB.extended.WP /
##   GBOTB.extended.TPL / GBOTB.extended.LCVP (not "GBMB"). WP = World Plants
##   taxonomy variant; TPL = The Plant List; LCVP = Leipzig Catalogue.
##   WP is used here as the most current classification.
##
## PLACEMENT: Scenario 3 (random placement within genus node)
##   Used for species not directly in the backbone. Species without a genus
##   match are grafted at the family node. Ungrafted species are documented.
##
## V.PhyloMaker2 citation: use citation("V.PhyloMaker2") to get the exact
##   current reference before publication — v2 paper citation UNVERIFIED.
##
## TREE BUILT:
##   tree_measured.nwk   — pruned to species with Tier 1-4 AGB estimates
##                         (~11,821 species; used for Stage 10b PGLMM fitting)
##
## NOTE ON tree_full:
##   Building a full tree for all ~287K BIEN species (with backbone-matched
##   families) takes ~19 hours on this hardware (24 sec / 100 species for
##   phylo.maker in Scenario 3). The PGLMM pipeline (Stages 10b–10d) only
##   requires tree_measured. The full tree is an optional future step.
##   Set BUILD_FULL_TREE=TRUE below to enable it.
##
## POLYTOMY WARNING:
##   Species grafted at genus/family nodes share zero within-node branch length.
##   These form polytomies — their phylogenetic covariance within the group = 1.
##   The PGLMM handles this via sparse Ainv, but do NOT interpret genus-level
##   BLUP agreement as evidence of phylogenetic signal in these species.
##
## FAMILY DATA:
##   The pipeline family column is all NA (never populated from BIEN queries).
##   Family is derived from genus using tips.info.WP bundled with V.PhyloMaker2
##   (72,570 species → 10,583 unique genera with families). Species with genera
##   not in the backbone (typically non-vascular plants, microalgae) are excluded.
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv  — full species list + tiers
##
## Outputs:
##   output/tree_measured.nwk          — Newick tree, measured species only
##   output/tree_placement_audit.csv   — per-species placement status
##
## Run from project root:
##   Rscript scripts/10a_build_phylo_tree.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages({
  library(data.table)
  library(V.PhyloMaker2)
  library(ape)
})

message("=== Stage 10a: Build phylogenetic trees ===")

## ---- Control flag: full tree (optional, ~19 hours) -------------------------
## Set to TRUE only if you need the full ~287K species tree.
## The PGLMM pipeline (10b-10d) works with tree_measured alone.
BUILD_FULL_TREE <- FALSE

## ---- Load species data -----------------------------------------------------
stopifnot(file.exists("output/plant_biomass_with_uncertainty.csv"))
dt <- fread("output/plant_biomass_with_uncertainty.csv",
            select = c("species_name", "family", "genus",
                       "growth_form_canonical", "agb_best_tier",
                       "higher_plant_group", "agb_method_flag"))
message("[10a] Loaded: ", nrow(dt), " species")
message("[10a] Species with non-NA genus: ", dt[!is.na(genus) & genus != "", .N])
message("[10a] Species with non-NA family: ", dt[!is.na(family) & family != "", .N])

## ---- Derive family from genus using V.PhyloMaker2 backbone -----------------
## The pipeline family column is empty. Use tips.info.WP (genus→family lookup)
## bundled in V.PhyloMaker2 to fill in family for all species with a known genus.
tips_info <- as.data.table(tips.info.WP)
genus_to_family <- unique(tips_info[, .(genus, family)])
setkey(genus_to_family, genus)
message("[10a] V.PhyloMaker2 genus→family lookup: ", nrow(genus_to_family), " genera")

## Join family from backbone where pipeline family is NA
dt[, genus_clean := trimws(genus)]
dt <- merge(dt, genus_to_family, by.x = "genus_clean", by.y = "genus",
            all.x = TRUE, suffixes = c("_pipeline", "_backbone"))
## Prefer backbone family (more reliable for tree matching)
dt[, family_use := ifelse(!is.na(family_backbone) & family_backbone != "",
                          family_backbone,
                   ifelse(!is.na(family_pipeline) & family_pipeline != "",
                          family_pipeline, NA_character_))]

n_with_family <- dt[!is.na(family_use) & family_use != "", .N]
message("[10a] Species with family after backbone lookup: ", n_with_family, " / ", nrow(dt))

## ---- Prepare species list for V.PhyloMaker2 --------------------------------
## V.PhyloMaker2 requires columns: species (underscore), genus, family

MEASUREMENT_TIERS <- c("1", "2", "3", "4")

## Measured species only (for tree_measured) — Tiers 1-4 only (CRITICAL PATH)
spp_meas <- unique(dt[agb_best_tier %in% MEASUREMENT_TIERS &
                      !is.na(genus_clean) & genus_clean != "" &
                      !is.na(family_use) & family_use != "",
  .(species = gsub(" ", "_", species_name),
    genus   = genus_clean,
    family  = family_use)])
message("[10a] Measured species (T1-T4) for tree: ", nrow(spp_meas))

if (nrow(spp_meas) == 0) stop("[10a] No measured species matched genus→family. Check genus column.")

spp_meas <- spp_meas[!duplicated(species)]

## All species with genus + family (for optional tree_full)
## Built lazily inside BUILD_FULL_TREE block below
if (BUILD_FULL_TREE) {
  spp_full <- unique(dt[!is.na(genus_clean) & genus_clean != "" &
                        !is.na(family_use) & family_use != "",
    .(species = gsub(" ", "_", species_name),
      genus   = genus_clean,
      family  = family_use)])
  spp_full <- spp_full[!duplicated(species)]
  message("[10a] Unique species for full tree: ", nrow(spp_full))
}

## ---- Build measured tree (CRITICAL PATH) -----------------------------------
message("[10a] Building measured tree (T1-T4 species, n=", nrow(spp_meas), ")...")
message("      Estimated time: ~", round(nrow(spp_meas) / 100 * 24 / 60), " minutes")

tree_meas_result <- tryCatch({
  phylo.maker(
    sp.list   = as.data.frame(spp_meas),
    tree      = GBOTB.extended.WP,
    nodes     = nodes.info.1.WP,
    scenarios = "S3"
  )
}, error = function(e) {
  message("[10a] ERROR building measured tree: ", conditionMessage(e))
  NULL
})

if (is.null(tree_meas_result)) {
  stop("[10a] Measured tree construction failed.")
}

tree_meas <- tree_meas_result$scenario.3
message("[10a] Measured tree built: ", length(tree_meas$tip.label), " tips")

## ---- Build full tree (OPTIONAL, ~19 hours) ---------------------------------
if (BUILD_FULL_TREE) {
  message("[10a] Building full tree (", nrow(spp_full), " species)...")
  message("      WARNING: Estimated time ~",
          round(nrow(spp_full) / 100 * 24 / 3600, 1), " hours")
  tree_full_result <- tryCatch({
    phylo.maker(
      sp.list   = as.data.frame(spp_full),
      tree      = GBOTB.extended.WP,
      nodes     = nodes.info.1.WP,
      scenarios = "S3"
    )
  }, error = function(e) {
    message("[10a] ERROR building full tree: ", conditionMessage(e))
    NULL
  })
  if (!is.null(tree_full_result)) {
    tree_full <- tree_full_result$scenario.3
    write.tree(tree_full, file = "output/tree_full.nwk")
    message("[10a] Full tree written: output/tree_full.nwk (", length(tree_full$tip.label), " tips)")
  } else {
    message("[10a] Full tree failed — skipping. Only tree_measured will be used.")
  }
} else {
  message("[10a] Skipping full tree build (BUILD_FULL_TREE=FALSE).")
  message("      Full tree not needed for PGLMM pipeline (10b-10d).")
  message("      Set BUILD_FULL_TREE=TRUE to build it (~19 hours).")
}
message("[10a] Generating placement audit...")

## V.PhyloMaker2 does not expose per-species placement status directly.
## Infer placement quality:
##   - Exact match: species tip label matches V.PhyloMaker2 backbone exactly
##   - Genus graft: genus found in backbone; species placed randomly within genus
##   - Family graft: genus NOT in backbone but family is
##   - Unplaced: neither genus nor family in backbone

## Backbone tip labels (genus_species format)
backbone_tips <- GBOTB.extended.WP$tip.label

## Backbone genera and families (from tips.info.WP lookup table)
backbone_genera   <- unique(tips.info.WP$genus)
backbone_families <- unique(tips.info.WP$family)

audit <- dt[!is.na(genus_clean) & genus_clean != "",
  .(species_name, genus = genus_clean, family = family_use,
    agb_best_tier, agb_method_flag)]
audit[, species_underscore := gsub(" ", "_", species_name)]

audit[, placement := fcase(
  species_underscore %in% backbone_tips,  "exact_match",
  genus              %in% backbone_genera, "genus_grafted",
  family             %in% backbone_families, "family_grafted",
  default = "unplaced"
)]

placement_summary <- audit[, .N, by = placement]
setorder(placement_summary, placement)

message("\n[10a] === Placement summary ===")
for (i in seq_len(nrow(placement_summary))) {
  message(sprintf("  %-20s %d species (%.1f%%)",
    placement_summary$placement[i],
    placement_summary$N[i],
    100 * placement_summary$N[i] / nrow(audit)))
}

## Also report for measured-only species — handle if audit has 0 rows
audit_meas <- audit[agb_best_tier %in% MEASUREMENT_TIERS]
placement_meas <- audit_meas[, .N, by = placement]
message("\n[10a] Measured species placement (T1-T4):")
for (i in seq_len(nrow(placement_meas))) {
  message(sprintf("  %-20s %d", placement_meas$placement[i], placement_meas$N[i]))
}

message("\n[10a] POLYTOMY NOTE: genus_grafted species share zero within-genus")
message("      branch length — their phylogenetic covariance within genus = 1.")
message("      Do not interpret genus-level BLUP agreement as independent signal.")

## ---- Write outputs ---------------------------------------------------------
dir.create("output", showWarnings = FALSE)

write.tree(tree_meas, file = "output/tree_measured.nwk")
message("[10a] Measured tree written: output/tree_measured.nwk")
message("      Tips: ", length(tree_meas$tip.label))

fwrite(audit, "output/tree_placement_audit.csv")
message("[10a] Placement audit written: output/tree_placement_audit.csv")
message("      Rows: ", nrow(audit))

## Write genus→family lookup so downstream scripts (10b, 10c, 10d) can fill
## the missing family column without loading V.PhyloMaker2 again.
fwrite(genus_to_family, "output/genus_family_lookup.csv")
message("[10a] Genus→family lookup written: output/genus_family_lookup.csv")

## Verify tree is ultrametric (required for BM/OU covariance)
ul_meas <- is.ultrametric(tree_meas, tol = 1e-4)
message("\n[10a] Ultrametric check:")
message("  tree_measured.nwk : ", if (ul_meas) "ULTRAMETRIC (OK)" else "NOT ULTRAMETRIC (WARNING)")

if (!ul_meas) {
  message("[10a] Non-ultrametric tree detected. Applying chronos() correction...")
  ## Use penalised likelihood to convert to ultrametric
  tree_meas_ul <- tryCatch(
    chronos(tree_meas, lambda = 1),
    error = function(e) {
      message("[10a] chronos() failed: ", conditionMessage(e), " — tree saved as-is")
      tree_meas
    }
  )
  if (inherits(tree_meas_ul, "phylo")) {
    write.tree(tree_meas_ul, file = "output/tree_measured_ultrametric.nwk")
    message("[10a] Ultrametric correction written: output/tree_measured_ultrametric.nwk")
  }
}

## Print V.PhyloMaker2 citation for provenance record
message("\n[10a] V.PhyloMaker2 citation (verify before use):")
tryCatch(print(citation("V.PhyloMaker2")), error = function(e) message("citation() failed"))

message("=== Stage 10a complete ===")
