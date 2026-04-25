dryad_search_seed_terms <- function() {
  data.frame(
    query_term = c(
      # --- Broad discovery ---
      "plant* trait*",
      # --- Leaf economics spectrum ---
      '"specific leaf area" plant',
      '"leaf area" plant',
      '"leaf dry matter content" plant',
      '"leaf nitrogen" plant',
      '"leaf phosphorus" plant',
      '"leaf carbon" plant',
      '"leaf chlorophyll" plant',
      '"leaf lifespan" plant',
      '"leaf water content" plant',
      # --- Stem structure ---
      '"wood density" plant',
      '"stem density" plant',
      '"bark thickness" plant',
      '"vessel diameter" xylem plant',
      # --- Whole-plant size ---
      '"plant height" trait',
      '"seed mass" plant',
      '"fruit mass" plant',
      # --- Gas exchange ---
      '"photosynthetic rate" plant',
      '"stomatal conductance" plant',
      # --- Root economics ---
      '"specific root length" plant',
      '"root tissue density" plant',
      # --- Hydraulics ---
      '"hydraulic conductivity" stem plant',
      '"cavitation resistance" plant',
      '"P50" xylem plant',
      '"turgor loss point" plant',
      '"huber value" plant',
      # --- Categorical ---
      '"growth form" plant trait',
      '"leaf phenology" plant',
      '"dispersal syndrome" plant'
    ),
    theme = c(
      "broad_trait_discovery",
      "leaf_economics", "leaf_economics", "leaf_economics",
      "leaf_economics", "leaf_economics", "leaf_economics",
      "leaf_economics", "leaf_economics", "leaf_economics",
      "stem_structure", "stem_structure", "stem_structure", "stem_structure",
      "size_structure", "reproduction", "reproduction",
      "gas_exchange", "gas_exchange",
      "root_economics", "root_economics",
      "hydraulics", "hydraulics", "hydraulics", "hydraulics", "hydraulics",
      "whole_plant", "whole_plant", "whole_plant"
    ),
    trait_focus = c(
      "mixed",
      "specific_leaf_area", "leaf_area", "leaf_dry_matter_content",
      "leaf_n", "leaf_p", "leaf_carbon",
      "leaf_chlorophyll", "leaf_lifespan", "leaf_water_content",
      "wood_density", "stem_specific_density", "bark_thickness", "xylem_vessel_diameter",
      "plant_height", "seed_mass", "fruit_mass",
      "photosynthetic_rate", "stomatal_conductance",
      "specific_root_length", "root_tissue_density",
      "stem_hydraulic_conductivity", "p50", "p50", "turgor_loss_point", "huber_value",
      "growth_form", "leaf_phenology", "dispersal_syndrome"
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
      "ldmc", "functional", "hydraulic", "conductivity", "stomatal", "photosynthesis",
      "cavitation", "p50", "turgor", "bark", "vessel", "dispersal", "phenology",
      "growth form", "chlorophyll", "carbon", "root length"
    ),
    measurement = c(
      "measured", "measurement", "common garden", "individual", "plot", "sample",
      "replicate", "morphology", "chemistry", "defense", "reproduction",
      "gas exchange", "vulnerability curve", "pressure volume", "pressure-volume"
    ),
    exclude = c(
      "animal", "microbe", "bacteria", "fungi", "fish", "bird", "mammal"
    )
  )
}
