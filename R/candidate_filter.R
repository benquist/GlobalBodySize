## GlobalBodySize/R/candidate_filter.R
## Score candidate datasets from API searches for body mass relevance
## Analogous to DryadPlantTraits/R/candidate_filter.R
## Higher score = more likely to contain direct body mass measurements

## ---- Keyword dictionaries for scoring ---------------------------------------

## Strong positive signals — high-confidence body mass content
.bm_strong_positive <- c(
  "body mass", "body size", "body weight", "wet mass", "dry mass",
  "live weight", "morphometrics", "length.weight", "mass.g",
  "body mass database", "body size database", "mass data",
  "adult mass", "species mass", "trait database"
)

## Taxon-specific positive signals
.bm_taxon_positive <- c(
  "mammal", "bird", "avian", "fish", "reptile", "amphibian", "frog",
  "salamander", "lizard", "snake", "bat", "rodent", "carnivore",
  "ungulate", "primate", "insect", "arthropod", "beetle", "ant",
  "zooplankton", "vertebrate", "herpetofauna", "squamate"
)

## Weak positive signals — may contain mass as secondary variable
.bm_weak_positive <- c(
  "morphology", "life history", "functional trait", "species trait",
  "allometry", "scaling", "physiology", "ecology", "macroecology",
  "museum specimen", "natural history collection", "biodiversity",
  "abundance", "population", "community ecology"
)

## Negative signals — likely not a body mass dataset
## IMPORTANT: Do NOT include plant anatomy terms here — they characterize legitimate
##   plant body size datasets (leaf mass, wood density, root biomass).
##   Plant-specific terms are scored via .bm_plant_positive below when group = plant.
.bm_negative <- c(
  "genetic", "genomic", "phylogeny", "sequence", "microbiome", "climate",
  "land use", "vegetation cover", "remote sensing", "satellite",
  "pollen", "fossil", "stratigraphic", "sediment", "paleoclimate",
  "seed germination", "chlorophyll", "photosynthesis", "stomatal"
)

## Plant-specific positive signals — add +2 when taxon_group_filter includes "plant"
.bm_plant_positive <- c(
  "plant trait", "leaf mass", "wood density", "root biomass",
  "stem mass", "above-ground biomass", "plant biomass", "seed mass"
)

## ---- Scoring function -------------------------------------------------------

score_candidate <- function(title, abstract, keywords, taxon_group_filter = NULL) {
  ## Combine all text fields, lowercase
  text <- tolower(paste(
    title    %||% "",
    abstract %||% "",
    keywords %||% "",
    sep = " "
  ))

  score <- 0

  ## Strong positive: +6 each
  strong_hits <- sum(vapply(.bm_strong_positive,
                            function(kw) grepl(kw, text, fixed = TRUE),
                            logical(1)))
  score <- score + strong_hits * 6

  ## Taxon positive: +3 each
  taxon_hits <- sum(vapply(.bm_taxon_positive,
                           function(kw) grepl(kw, text, fixed = TRUE),
                           logical(1)))
  score <- score + taxon_hits * 3

  ## Weak positive: +1 each
  weak_hits <- sum(vapply(.bm_weak_positive,
                          function(kw) grepl(kw, text, fixed = TRUE),
                          logical(1)))
  score <- score + weak_hits * 1

  ## Negative: -4 each
  neg_hits <- sum(vapply(.bm_negative,
                         function(kw) grepl(kw, text, fixed = TRUE),
                         logical(1)))
  score <- score - neg_hits * 4

  ## Plant positive: +2 each when plant group is in scope
  if (!is.null(taxon_group_filter) && "plant" %in% taxon_group_filter) {
    plant_hits <- sum(vapply(.bm_plant_positive,
                             function(kw) grepl(kw, text, fixed = TRUE),
                             logical(1)))
    score <- score + plant_hits * 2
  }

  ## Taxon group filter bonus: +5 if matches requested group
  if (!is.null(taxon_group_filter)) {
    if (any(vapply(taxon_group_filter,
                   function(kw) grepl(kw, text, fixed = TRUE),
                   logical(1)))) {
      score <- score + 5
    }
  }

  max(score, 0)
}

## Apply scoring to a data.frame of candidate datasets
score_candidates <- function(candidates_df, taxon_group_filter = NULL) {
  stopifnot(is.data.frame(candidates_df))
  candidates_df$candidate_score <- mapply(
    score_candidate,
    title    = candidates_df$title    %||% "",
    abstract = candidates_df$abstract %||% "",
    keywords = candidates_df$keywords %||% "",
    MoreArgs = list(taxon_group_filter = taxon_group_filter)
  )
  candidates_df[order(-candidates_df$candidate_score), , drop = FALSE]
}

`%||%` <- `%||%` %||% function(x, y) if (is.null(x) || !length(x)) y else x
