## Global_Plant_BodySize/scripts/10a_build_phylo_tree.R
## Stage 10a: Build phylogenetic trees for all BIEN species using
##   V.PhyloMaker2 with the Smith & Brown 2018 GBMB backbone.
##
## BACKBONE: GBMB (Gymnosperm- and angiosperm-Backbone Megatree)
##   Smith SA & Brown JW (2018) Constructing a broadly inclusive seed plant
##   phylogeny. American Journal of Botany 105(3):302-314.
##   DOI: 10.3732/ajb.1700476  [VERIFIED]
##
## PLACEMENT: Scenario 3 (random placement within genus node)
##   Used for species not directly in the backbone. Species without a genus
##   match are grafted at the family node. Ungrafted species are documented.
##
## V.PhyloMaker2 citation: use citation("V.PhyloMaker2") to get the exact
##   current reference before publication — v2 paper citation UNVERIFIED.
##
## TWO TREES GENERATED:
##   tree_measured.nwk   — pruned to species with Tier 1-4 AGB estimates
##                         (~11,821 species; used for Stage 10b PGLMM fitting)
##   tree_full.nwk       — all BIEN species with AGB estimates or GF data
##                         (stored for Stage 2 BLUP prediction covariance structure)
##
## POLYTOMY WARNING:
##   Species grafted at genus/family nodes share zero within-node branch length.
##   These form polytomies — their phylogenetic covariance within the group = 1.
##   The PGLMM handles this via sparse Ainv, but do NOT interpret genus-level
##   BLUP agreement as evidence of phylogenetic signal in these species.
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv  — full species list + tiers
##
## Outputs:
##   output/tree_measured.nwk          — Newick tree, measured species only
##   output/tree_full.nwk              — Newick tree, all species
##   output/tree_placement_audit.csv   — per-species placement status:
##       n_exact, n_genus_grafted, n_family_grafted, n_unplaced
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

## ---- Load species data -----------------------------------------------------
stopifnot(file.exists("output/plant_biomass_with_uncertainty.csv"))
dt <- fread("output/plant_biomass_with_uncertainty.csv",
            select = c("species_name", "family", "genus",
                       "growth_form_canonical", "agb_best_tier",
                       "higher_plant_group", "agb_method_flag"))
message("[10a] Loaded: ", nrow(dt), " species")

## ---- Prepare species list for V.PhyloMaker2 --------------------------------
## V.PhyloMaker2 requires a data frame with columns: species, genus, family
## 'species' must be the full binomial (Genus_species with underscore)

## Subset to species with AGB data or GF knowledge (exclude truly no-data)
MEASUREMENT_TIERS <- c("1", "2", "3", "4")

## All species (for tree_full)
spp_full <- unique(dt[!is.na(genus) & !is.na(family),
  .(species = gsub(" ", "_", species_name),
    genus   = genus,
    family  = family)])
message("[10a] Unique species for full tree: ", nrow(spp_full))

## Measured species only (for tree_measured) — Tiers 1-4 only
spp_meas <- unique(dt[agb_best_tier %in% MEASUREMENT_TIERS &
                      !is.na(genus) & !is.na(family),
  .(species = gsub(" ", "_", species_name),
    genus   = genus,
    family  = family)])
message("[10a] Measured species (T1-T4) for pruned tree: ", nrow(spp_meas))

## Remove duplicates (species can appear once per species list)
spp_full <- spp_full[!duplicated(species)]
spp_meas <- spp_meas[!duplicated(species)]

## ---- Build full tree -------------------------------------------------------
message("[10a] Building full tree via V.PhyloMaker2 (Scenario 3 + GBMB)...")
message("      This may take several minutes for large species lists...")

## Use GBMB backbone — access via GBMB object bundled with V.PhyloMaker2
## phylo.maker() arguments:
##   sp.list  = data.frame with species, genus, family columns
##   tree     = backbone tree (GBMB)
##   nodes    = node matrix matching backbone (GBMB.nodes)
##   scenarios = "S3" (random placement within genus)

tree_full_result <- tryCatch({
  phylo.maker(
    sp.list   = as.data.frame(spp_full),
    tree      = GBMB,
    nodes     = nodes.info.1,
    scenarios = "S3"
  )
}, error = function(e) {
  message("[10a] ERROR building full tree: ", conditionMessage(e))
  NULL
})

if (is.null(tree_full_result)) {
  stop("[10a] Full tree construction failed. Check species column format and V.PhyloMaker2 version.")
}

tree_full <- tree_full_result$scenario.3
message("[10a] Full tree: ", length(tree_full$tip.label), " tips")

## ---- Build measured tree ---------------------------------------------------
message("[10a] Building measured tree (T1-T4 species only)...")

tree_meas_result <- tryCatch({
  phylo.maker(
    sp.list   = as.data.frame(spp_meas),
    tree      = GBMB,
    nodes     = nodes.info.1,
    scenarios = "S3"
  )
}, error = function(e) {
  message("[10a] ERROR building measured tree: ", conditionMessage(e))
  NULL
})

if (is.null(tree_meas_result)) {
  ## Fallback: prune full tree to measured species
  message("[10a] Falling back to pruning full tree to measured species...")
  meas_tips <- spp_meas$species
  tips_in_full <- intersect(meas_tips, tree_full$tip.label)
  tree_meas <- keep.tip(tree_full, tips_in_full)
  message("[10a] Pruned tree: ", length(tree_meas$tip.label), " tips")
} else {
  tree_meas <- tree_meas_result$scenario.3
  message("[10a] Measured tree: ", length(tree_meas$tip.label), " tips")
}

## ---- Placement audit -------------------------------------------------------
message("[10a] Generating placement audit...")

## V.PhyloMaker2 does not expose per-species placement status directly.
## Infer placement quality:
##   - Exact match: species tip label matches V.PhyloMaker2 backbone exactly
##   - Genus graft: genus found in backbone; species placed randomly within genus
##   - Family graft: genus NOT in backbone but family is
##   - Unplaced: neither genus nor family in backbone

## Backbone tip labels (genus_species format)
backbone_tips <- GBMB$tip.label  ## all GBMB tips

## Backbone genera and families (parse from GBMB tip + nodes)
backbone_genera   <- unique(gsub("_.*", "", backbone_tips))
backbone_families <- unique(nodes.info.1$family.APG)

audit <- dt[!is.na(genus) & !is.na(family),
  .(species_name, genus, family, agb_best_tier, agb_method_flag)]
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

## Also report for measured-only species
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

write.tree(tree_full, file = "output/tree_full.nwk")
message("[10a] Full tree written: output/tree_full.nwk")
message("      Tips: ", length(tree_full$tip.label))

write.tree(tree_meas, file = "output/tree_measured.nwk")
message("[10a] Measured tree written: output/tree_measured.nwk")
message("      Tips: ", length(tree_meas$tip.label))

fwrite(audit, "output/tree_placement_audit.csv")
message("[10a] Placement audit written: output/tree_placement_audit.csv")
message("      Rows: ", nrow(audit))

## Verify trees are ultrametric (required for BM/OU covariance)
ul_full <- is.ultrametric(tree_full, tol = 1e-4)
ul_meas <- is.ultrametric(tree_meas, tol = 1e-4)
message("\n[10a] Ultrametric check:")
message("  tree_full.nwk     : ", if (ul_full) "ULTRAMETRIC (OK)" else "NOT ULTRAMETRIC (WARNING)")
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
