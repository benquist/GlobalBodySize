dryad_search_seed_terms <- function() {
  data.frame(
    query_term = c(
      "plant* trait*",
      '"specific leaf area" plant',
      '"leaf area" plant',
      '"wood density" plant',
      '"seed mass" plant',
      '"plant height" trait',
      '"leaf nitrogen" plant',
      '"leaf phosphorus" plant',
      '"leaf dry matter content" plant',
      '"stem density" plant'
    ),
    theme = c(
      "broad_trait_discovery",
      "leaf_economics",
      "leaf_morphology",
      "stem_structure",
      "reproduction",
      "size_structure",
      "leaf_chemistry",
      "leaf_chemistry",
      "leaf_economics",
      "stem_structure"
    ),
    trait_focus = c(
      "mixed",
      "specific_leaf_area",
      "leaf_area",
      "wood_density",
      "seed_mass",
      "plant_height",
      "leaf_n",
      "leaf_p",
      "leaf_dry_matter_content",
      "stem_specific_density"
    ),
    stringsAsFactors = FALSE
  )
}

dryad_candidate_signal_terms <- function() {
  list(
    plant = c(
      "plant", "leaf", "seed", "wood", "stem", "tree", "shrub", "herb",
      "floral", "root", "forest", "grass", "species", "vegetation"
    ),
    trait = c(
      "trait", "traits", "specific leaf area", "sla", "leaf area", "wood density",
      "seed mass", "height", "nitrogen", "phosphorus", "leaf dry matter content",
      "ldmc", "functional"
    ),
    measurement = c(
      "measured", "measurement", "common garden", "individual", "plot", "sample",
      "replicate", "morphology", "chemistry", "defense", "reproduction"
    ),
    exclude = c(
      "animal", "microbe", "bacteria", "fungi", "fish", "bird", "mammal"
    )
  )
}
