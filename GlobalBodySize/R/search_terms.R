## GlobalBodySize/R/search_terms.R
## Search vocabulary for programmatic API harvest across Dryad, Zenodo, Figshare, OSF
## Modeled after DryadPlantTraits/R/search_terms.R
## All terms are designed as REST API keyword queries (phrase-quoted where appropriate)

globalsize_search_seed_terms <- function() {
  data.frame(
    query_term = c(

      # --- General body mass / body size (broad discovery) ---
      '"body mass" species dataset',
      '"body size" species dataset',
      '"body weight" animal species',
      '"wet mass" animal species',
      '"dry mass" animal body',
      '"live weight" species data',
      '"body mass" trait database',
      '"body mass" compendium vertebrate',
      '"body size" allometry dataset',

      # --- Mammal body mass ---
      '"mammal body mass"',
      '"mammal* mass" trait',
      '"rodent body mass"',
      '"bat body mass"',
      '"carnivore body mass"',
      '"ungulate body mass"',
      '"primate body mass"',
      '"marsupial body mass"',
      '"mammal life history" body mass',
      '"small mammal" body mass dataset',

      # --- Bird body mass / morphology ---
      '"bird body mass"',
      '"avian body mass"',
      '"avian morphology" mass',
      '"bird morphometrics"',
      '"passerine body mass"',
      '"raptor body mass"',
      '"waterbird body mass"',
      '"avian life history" body mass',

      # --- Fish body mass / length-weight ---
      '"fish body mass"',
      '"length-weight relationship" fish',
      '"fish wet mass"',
      '"fish weight" species data',
      '"length weight" fish species data',
      '"teleost body mass"',
      '"elasmobranch body mass"',
      '"weight-at-age" fish species',

      # --- Reptile body mass ---
      '"reptile body mass"',
      '"snake body mass"',
      '"lizard body mass"',
      '"herpetofauna body size"',
      '"squamate body mass"',
      '"reptile trait" body size dataset',

      # --- Amphibian body mass ---
      '"amphibian body mass"',
      '"frog body mass"',
      '"salamander body mass"',
      '"anuran body size"',
      '"amphibian life history" body size',

      # --- Insect / arthropod body mass ---
      '"insect body mass"',
      '"arthropod body size"',
      '"beetle body mass"',
      '"invertebrate body mass"',
      '"insect morphometrics"',
      '"ant body mass"',
      '"insect biomass" species',
      '"arthropod biomass" dataset',

      # --- Marine and zooplankton ---
      '"zooplankton body mass"',
      '"zooplankton body size"',
      '"marine organism body mass"',
      '"fish length weight" marine',

      # --- Allometry (metabolic scaling) ---
      '"body mass allometry"',
      '"metabolic scaling" body mass',
      '"allometric scaling" mass exponent',
      '"interspecific allometry" body mass',
      '"intraspecific allometry" mass',
      '"mass scaling" species dataset',
      '"Kleiber" metabolic body mass data',

      # --- Plant body size analogues ---
      '"seed mass" species global dataset',
      '"plant height" species trait data',
      '"above-ground biomass" species dataset',
      '"plant biomass" allometry dataset',
      '"stem mass" plant species',

      # --- Museum specimen and collection data ---
      '"museum specimen" body mass',
      '"natural history collection" measurements',
      '"specimen weight" vertebrate collection',
      '"banded" body mass bird',

      # --- Data paper framing terms ---
      '"body mass database"',
      '"body size database"',
      '"body mass compilation" species',
      '"life history" body mass data',
      '"trait database" body mass',
      '"functional traits" body mass vertebrate',
      '"species traits" body mass dataset',
      '"global database" body mass',
      '"body size" macroecology dataset'

    ),

    theme = c(
      # general (9)
      rep("general_body_mass", 9),
      # mammal (10)
      rep("mammal", 10),
      # bird (8)
      rep("bird", 8),
      # fish (8)
      rep("fish", 8),
      # reptile (6)
      rep("reptile", 6),
      # amphibian (5)
      rep("amphibian", 5),
      # insect/arthropod (8)
      rep("arthropod", 8),
      # marine/zooplankton (4)
      rep("marine", 4),
      # allometry (7)
      rep("allometry", 7),
      # plant (5)
      rep("plant", 5),
      # museum/specimen (4)
      rep("specimen", 4),
      # data paper framing (9)
      rep("data_paper", 9)
    ),

    stringsAsFactors = FALSE
  )
}
