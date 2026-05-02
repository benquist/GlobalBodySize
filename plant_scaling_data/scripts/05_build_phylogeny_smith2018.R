# scripts/05_build_phylogeny_smith2018.R
# NOTE: Requires V.PhyloMaker2 (install.packages("V.PhyloMaker2") from CRAN)
# Tree source: Smith SA & Brown JW (2018) Constructing a broadly inclusive seed plant phylogeny.
# American Journal of Botany 105(3):302-314. DOI: 10.1002/ajb2.1019

library(V.PhyloMaker2)
library(ape)
library(dplyr)
library(readr)

proj_dir <- normalizePath(".")

dir.create(file.path(proj_dir, "data/processed"), showWarnings = FALSE, recursive = TRUE)

# ── SECTION A: Load species means ─────────────────────────────────────────────

ne_species_means   <- readRDS(file.path(proj_dir, "data/processed/ne_species_means.rds"))
baad_species_means <- readRDS(file.path(proj_dir, "data/processed/baad_species_means.rds"))

# ── SECTION B: Build species list for phylo.maker() ───────────────────────────

ne_sp <- ne_species_means |>
  rename(species = taxa) |>
  select(species, genus) |>
  mutate(family = NA_character_)

baad_sp <- baad_species_means |>
  rename(species = speciesMatched) |>
  select(species, genus) |>
  mutate(family = NA_character_)

species_list <- bind_rows(ne_sp, baad_sp) |>
  distinct(species, .keep_all = TRUE) |>
  select(species, genus, family)

cat("Total unique species for tree:", nrow(species_list), "\n")

# ── SECTION C: Build tree ──────────────────────────────────────────────────────

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

pruned_tree <- tree_out$scenario.2
cat("Tree tips:", ape::Ntip(pruned_tree), "\n")

# ── SECTION D: Tree validation ────────────────────────────────────────────────

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
pruned_tree <- ape::multi2di(pruned_tree, random = TRUE)

cat("Is ultrametric:", ape::is.ultrametric(pruned_tree, tol = 1e-5), "\n")
cat("Is binary:",      ape::is.binary(pruned_tree), "\n")

# ── SECTION E: Match table ────────────────────────────────────────────────────
# V.PhyloMaker2 tip labels use underscores (Genus_species); convert for matching
species_underscore <- gsub(" ", "_", species_list$species)

match_table <- data.frame(
  species           = species_list$species,
  species_underscore = species_underscore,
  in_tree           = species_underscore %in% pruned_tree$tip.label
)

cat("Matched to tree:", sum(match_table$in_tree), "/", nrow(match_table), "\n")

write_csv(match_table, file.path(proj_dir, "data/processed/pgls_tree_match_table.csv"))

# ── SECTION F: Save ───────────────────────────────────────────────────────────

saveRDS(pruned_tree, file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.rds"))
ape::write.tree(pruned_tree, file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.tre"))
