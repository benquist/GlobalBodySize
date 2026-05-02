# scripts/05_build_phylogeny_smith2018.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 5 of 6. Build a species-level phylogenetic tree for the
#           combined Niklas-Enquist + BAAD species list using the Smith &
#           Brown (2018) megaphylogeny. Validate the tree and write a species
#           match table so that species coverage can be inspected before PGLS.
#
# NOTE:     Requires V.PhyloMaker2 (install.packages("V.PhyloMaker2") from CRAN)
#
# CITATION: Smith SA & Brown JW (2018) Constructing a broadly inclusive seed
#           plant phylogeny. American Journal of Botany 105(3):302-314.
#           DOI: 10.1002/ajb2.1019
#
# INPUTS:   data/processed/ne_species_means.rds
#           data/processed/baad_species_means.rds
#
# OUTPUTS:  data/processed/pgls_tree_smith2018_s2.rds   — R phylo object
#           data/processed/pgls_tree_smith2018_s2.tre   — Newick text file
#           data/processed/pgls_tree_match_table.csv    — species coverage table
#
# KEY CONCEPTS:
#   • Why use a phylogeny for allometric analysis?
#     Related species share evolutionary history and therefore tend to be more
#     similar to each other than expected by chance (phylogenetic signal).
#     Standard OLS and SMA regressions assume observations are independent,
#     which is violated when species are phylogenetically clustered. PGLS
#     corrects for this by scaling residual variance according to the
#     phylogenetic covariance matrix (see script 06).
#
#   • Smith & Brown (2018) megaphylogeny: a time-calibrated, broadly inclusive
#     seed plant phylogeny. V.PhyloMaker2::GBOTB.extended.WP extends the
#     original GBOTB tree (Jin & Qian 2019) and is used here as the backbone.
#
#   • Scenario S2 (phylo.maker): places missing species (those not in the
#     backbone tree) at the midpoint of their genus or family stem branch.
#     This is a reasonable default for broad allometric analyses. An alternative
#     is S3 (random placement), but S2 is more reproducible. Any species not
#     matching even a genus in the backbone will be dropped entirely.
#
#   • Ultrametricity requirement: PGLS via caper assumes an ultrametric tree
#     (all tips equidistant from the root, i.e. the tree is time-calibrated).
#     Small floating-point deviations from ultrametricity are common after
#     grafting operations; force.ultrametric() corrects them by extending short
#     terminal branches.
#
#   • Polytomies: multi-way splits in the backbone tree are resolved to binary
#     splits with zero-length branches using multi2di(). This is required
#     because caper's internal matrix operations assume a binary tree.
#     set.seed(42) ensures that the random ordering of polytomy resolutions is
#     reproducible across runs.
# ─────────────────────────────────────────────────────────────────────────────

library(V.PhyloMaker2) # Smith & Brown (2018) megaphylogeny tools
library(ape)           # phylogenetic tree manipulation
library(dplyr)         # data wrangling
library(readr)         # CSV output

# proj_dir: resolves to an absolute path, making file references portable
# when the script is run from different working directories (e.g. via Rscript).
proj_dir <- normalizePath(".")

dir.create(file.path(proj_dir, "data/processed"), showWarnings = FALSE, recursive = TRUE)

# ── SECTION A: Load species means ─────────────────────────────────────────────
# These are the outputs of script 04. Species names must be in "Genus species"
# format (two words, space-separated) — this is what phylo.maker() expects.
ne_species_means   <- readRDS(file.path(proj_dir, "data/processed/ne_species_means.rds"))
baad_species_means <- readRDS(file.path(proj_dir, "data/processed/baad_species_means.rds"))

# ── SECTION B: Build species list for phylo.maker() ───────────────────────────
# phylo.maker() requires a data frame with three columns: species, genus, family.
# 'family' is left as NA here and will be inferred from the backbone tree.
# Providing family can improve placement of unmatched species, so if family
# information is available from a taxonomy lookup (TNRS, BIEN, etc.), adding
# it here is worthwhile.

ne_sp <- ne_species_means |>
  rename(species = taxa) |>
  select(species, genus) |>
  mutate(family = NA_character_) # set to NA; phylo.maker will infer from backbone

baad_sp <- baad_species_means |>
  rename(species = speciesMatched) |>
  select(species, genus) |>
  mutate(family = NA_character_)

# Combine both datasets and deduplicate species. The same species may appear in
# both NE and BAAD; distinct() retains only one row per species for the tree.
# The tree is built once for all species; per-dataset pruning occurs in script 06.
species_list <- bind_rows(ne_sp, baad_sp) |>
  distinct(species, .keep_all = TRUE) |>
  select(species, genus, family)

cat("Total unique species for tree:", nrow(species_list), "\n")

# ── SECTION C: Build tree ──────────────────────────────────────────────────────
# phylo.maker() grafts each species in species_list onto the GBOTB backbone.
#   sp.list   = species × genus × family data frame (as built above)
#   tree      = GBOTB.extended.WP: the extended seed plant megaphylogeny
#   nodes     = nodes.info.1.WP: node annotation table for the WP version
#   scenarios = "S2": midpoint placement for missing taxa (see header)
#
# The tryCatch wrapper provides a clear error message if V.PhyloMaker2 is not
# installed, rather than an opaque R error about a missing object.
tree_out <- tryCatch({
  V.PhyloMaker2::phylo.maker(
    sp.list   = species_list,
    tree      = V.PhyloMaker2::GBOTB.extended.WP,
    nodes     = V.PhyloMaker2::nodes.info.1.WP,
    scenarios = "S2"
  )
}, error = function(e) {
  message("phylo.maker() failed: ", conditionMessage(e))
  NULL
})

if (is.null(tree_out)) {
  stop("Tree building failed. Ensure V.PhyloMaker2 is installed: install.packages('V.PhyloMaker2')")
}

# Extract the Scenario 2 tree (midpoint placement for unmatched taxa).
pruned_tree <- tree_out$scenario.2
cat("Tree tips:", ape::Ntip(pruned_tree), "\n")

# ── SECTION D: Tree validation ────────────────────────────────────────────────
# PGLS via caper requires (1) an ultrametric tree and (2) a fully binary tree.

# Ultrametricity check: small numerical deviations (< 1e-5) are common after
# grafting. force.ultrametric(method = "extend") stretches short terminal
# branches to restore ultrametricity without altering internal topology.
# If phytools is not available, a non-ultrametric tree is passed through with
# a warning; caper::pgls() may still run but results should be viewed cautiously.
if (!ape::is.ultrametric(pruned_tree, tol = 1e-5)) {
  pruned_tree <- tryCatch({
    phytools::force.ultrametric(pruned_tree, method = "extend")
  }, error = function(e) {
    warning("phytools::force.ultrametric() not available or failed; proceeding with non-ultrametric tree: ",
            conditionMessage(e))
    pruned_tree
  })
}

set.seed(42)  # document seed for reproducibility of multi2di() polytomy resolution
# Resolve polytomies to binary splits. random = TRUE assigns zero-length
# branches randomly among the polytomy members; set.seed(42) above ensures
# this step is reproducible. Zero-length branches contribute zero covariance
# in the PGLS model, so the resolution strategy has minimal influence on
# results, but reproducibility matters for review and replication.
pruned_tree <- ape::multi2di(pruned_tree, random = TRUE)

# Confirm tree properties after corrections. FALSE for either line indicates
# a problem that should be investigated before running script 06.
cat("Is ultrametric:", ape::is.ultrametric(pruned_tree, tol = 1e-5), "\n")
cat("Is binary:",      ape::is.binary(pruned_tree), "\n")

# ── SECTION E: Match table ────────────────────────────────────────────────────
# V.PhyloMaker2 tip labels use underscores ("Genus_species") whereas the input
# species list uses spaces ("Genus species"). Convert for matching, then record
# which species were successfully placed in the tree.
# Inspect pgls_tree_match_table.csv to identify dropped species. A low match
# rate (< ~60%) may reflect widespread taxonomic synonym issues that should
# be resolved in script 02 before re-running the tree build.
species_underscore <- gsub(" ", "_", species_list$species)

match_table <- data.frame(
  species            = species_list$species,
  species_underscore = species_underscore,
  in_tree            = species_underscore %in% pruned_tree$tip.label
)

cat("Matched to tree:", sum(match_table$in_tree), "/", nrow(match_table), "\n")

write_csv(match_table, file.path(proj_dir, "data/processed/pgls_tree_match_table.csv"))

# ── SECTION F: Save ───────────────────────────────────────────────────────────
# RDS: loaded directly by script 06 for PGLS.
# Newick (.tre): portable format for use in other software (FigTree, iTOL, ete3).
saveRDS(pruned_tree, file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.rds"))
ape::write.tree(pruned_tree, file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.tre"))
