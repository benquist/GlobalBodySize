## Global_Plant_BodySize/R/growth_form_vocab.R
## Canonical growth form vocabulary, BIEN string mappings, and special group flags.
##
## Special group flags implemented here:
##   is_graminoid — family in (Poaceae, Cyperaceae, Juncaceae)
##   is_bamboo    — subfamily Bambusoideae OR genus in curated bamboo genus list
##   is_bryophyte — phylum in bryophyte phyla (always FALSE for BIEN; placeholder)
##
## Bamboo genus list source:
##   Kelchner SA & Bamboo Phylogeny Group (2013). Higher level phylogenetic
##   relationships within the bamboos (Poaceae: Bambusoideae) based on five
##   plastid markers. Molecular Phylogenetics and Evolution 67(2):404-413.
##   DOI: 10.1016/j.ympev.2013.02.005  -- UNVERIFIED confirm DOI
##   NOTE: Genus-level list is curated from GBIF Backbone; not exhaustive for
##         all ~1,400 bamboo species. Subfamily detection is preferred when available.
##
## Written by: Global_Plant_BodySize pipeline (ecology-user agent, 2026-05-11)

source(file.path(dirname(sys.frame(1)$ofile), "plant_size_schema.R"))

## ---- Canonical growth form vocabulary ---------------------------------------
## This is the controlled vocabulary used in all output tables.
## Any value not in this list indicates a mapping failure.

plantsize_growth_form_vocab <- function() {
  c(
    "tree",
    "shrub",
    "subshrub",    # dwarf shrub / subshrub
    "herb",        # forb / herbaceous non-graminoid
    "graminoid",   # grass, sedge, rush — family-based flag; see flag_graminoid()
    "bamboo",      # woody graminoid, subfamily Bambusoideae; subset of graminoid
    "vine",        # liana, climber (woody or herbaceous)
    "epiphyte",    # non-parasitic epiphyte (including lithophytes)
    "aquatic",     # submerged, emergent, or floating aquatic plant
    "parasite",    # hemi- or holoparasite
    "unknown"      # no growth form data available
  )
}

## ---- BIEN growth form string → canonical map --------------------------------
## BIEN trait "growth form" returns freetext values.
## Maps tolower(trimws(bien_value)) → canonical.
## Ambiguous cases (e.g. "shrub/tree") are mapped conservatively to the
## more specific category. Update this map as novel BIEN strings are discovered.

plantsize_bien_growth_form_map <- function() {
  data.frame(
    bien_value = c(
      ## tree forms
      "tree", "trees", "tree/shrub", "shrub/tree", "arborescent", "woody tree",
      "palm tree", "palm",
      ## shrub forms
      "shrub", "shrubs", "woody shrub", "shrublet", "shrubby",
      ## subshrub
      "subshrub", "sub-shrub", "dwarf shrub", "suffrutex",
      ## herb forms
      "herb", "forb", "forb/herb", "herbaceous", "annual", "annual herb",
      "perennial herb", "perennial", "geophyte", "succulent herb", "cactus",
      "succulent", "fern", "pteridophyte",
      ## graminoid forms (non-bamboo; family check is authoritative)
      "grass", "graminoid", "graminoid/herb", "sedge", "rush", "graminoid herb",
      ## vine / climber
      "vine", "liana", "climber", "woody vine", "climbing herb", "twining",
      "scandent",
      ## epiphyte
      "epiphyte", "epiphytic", "lithophyte",
      ## aquatic
      "aquatic", "aquatic herb", "submerged aquatic", "floating",
      "emergent aquatic", "hydrophyte",
      ## parasite
      "parasite", "hemiparasite", "holoparasite", "parasitic plant"
    ),
    canonical = c(
      ## tree
      "tree", "tree", "tree", "tree", "tree", "tree",
      "tree", "tree",
      ## shrub (shrub/tree → tree; see note above)
      "shrub", "shrub", "shrub", "shrub", "shrub",
      ## subshrub
      "subshrub", "subshrub", "subshrub", "subshrub",
      ## herb
      "herb", "herb", "herb", "herb", "herb", "herb",
      "herb", "herb", "herb", "herb", "herb",
      "herb", "herb", "herb",
      ## graminoid
      "graminoid", "graminoid", "graminoid", "graminoid", "graminoid", "graminoid",
      ## vine
      "vine", "vine", "vine", "vine", "vine", "vine",
      "vine",
      ## epiphyte
      "epiphyte", "epiphyte", "epiphyte",
      ## aquatic
      "aquatic", "aquatic", "aquatic", "aquatic",
      "aquatic", "aquatic",
      ## parasite
      "parasite", "parasite", "parasite", "parasite"
    ),
    stringsAsFactors = FALSE
  )
}

## ---- Graminoid family list --------------------------------------------------
## Authoritative flag: a species is graminoid if its family is in this list.
## This overrides the BIEN growth_form string when family data is available.

plantsize_graminoid_families <- function() {
  c("Poaceae", "Cyperaceae", "Juncaceae")
}

## ---- Bamboo genus list (curated backup) ------------------------------------
## Used when subfamily information is not available in BIEN records.
## Covers major bamboo genera in the New World and globally traded species.
## This list is NOT exhaustive; subfamily == "Bambusoideae" is preferred.
## Herbaceous bamboos (Olyreae tribe) are included; they are graminoids
## but not typically called "bamboo" in common usage — flag them separately
## if tribe-level data becomes available.

plantsize_bamboo_genera <- function() {
  c(
    ## New World woody bamboos (Bambuseae, Chusqueinae, Guaduinae)
    "Chusquea", "Guadua", "Arundinaria", "Otatea", "Rhipidocladum",
    "Aulonemia", "Merostachys", "Arthrostylidium", "Apoclada",
    "Atractantha", "Colanthelia", "Elytrostachys", "Eremocaulon",
    "Glaziophyton", "Myriocladus", "Olmeca",
    ## Old World / cosmopolitan genera (in BIEN through cultivation or naturalization)
    "Bambusa", "Dendrocalamus", "Phyllostachys", "Fargesia",
    "Yushania", "Pseudosasa", "Sasa", "Pleioblastus",
    "Gigantochloa", "Thyrsostachys", "Schizostachyum", "Cephalostachyum",
    "Nastus", "Ochlandra",
    ## Herbaceous bamboos (Olyreae) — present in New World understory
    "Olyra", "Pariana"
  )
}

## ---- Bryophyte phyla (for future non-BIEN integration) ---------------------
## BIEN does NOT contain bryophytes. These phyla are provided as a reference
## for future pipeline stages that may integrate bryophyte body size data
## from GBIF, literature, or BryoFlor-type databases.

plantsize_bryophyte_phyla <- function() {
  c("Bryophyta", "Marchantiophyta", "Anthocerotophyta")
}

## ---- Map a vector of BIEN growth form strings to canonical -----------------
## Returns canonical growth form vector; unmapped strings → "unknown".

map_bien_growth_form <- function(bien_values) {
  stopifnot(is.character(bien_values) || all(is.na(bien_values)))
  map_df <- plantsize_bien_growth_form_map()
  lv     <- tolower(trimws(as.character(bien_values)))
  lmap   <- tolower(map_df$bien_value)

  result <- vapply(lv, function(x) {
    if (is.na(x) || x == "") return("unknown")
    idx <- which(lmap == x)
    if (length(idx) > 0) map_df$canonical[idx[1]] else "unknown"
  }, character(1), USE.NAMES = FALSE)

  result
}

## ---- Flag graminoid from family name ----------------------------------------
## Returns logical vector; TRUE if family is in graminoid family list.
## family_vec: character vector of family names.

flag_graminoid <- function(family_vec) {
  family_vec %in% plantsize_graminoid_families()
}

## ---- Flag bamboo from genus name and/or subfamily --------------------------
## Returns logical vector; TRUE if bamboo is indicated.
## Prefers subfamily == "Bambusoideae" when available; falls back to genus list.
## genus_vec:     character vector of genus names
## subfamily_vec: character vector (or NULL) of subfamily names

flag_bamboo <- function(genus_vec, subfamily_vec = NULL) {
  bamboo_genera <- plantsize_bamboo_genera()
  is_bamboo_genus <- genus_vec %in% bamboo_genera

  if (!is.null(subfamily_vec)) {
    is_bamboo_sf <- !is.na(subfamily_vec) & trimws(subfamily_vec) == "Bambusoideae"
    return(is_bamboo_genus | is_bamboo_sf)
  }

  is_bamboo_genus
}

## ---- Resolve canonical growth form with family-based override ---------------
## Applies this priority order:
##   1. If family is in graminoid list AND is_bamboo → "bamboo"
##   2. If family is in graminoid list              → "graminoid"
##   3. Otherwise → mapped_growth_form from BIEN string
## This ensures family-based flags take precedence over BIEN freetext.

resolve_canonical_growth_form <- function(mapped_growth_form, family_vec,
                                          genus_vec, subfamily_vec = NULL) {
  is_gram   <- flag_graminoid(family_vec)
  is_bamb   <- flag_bamboo(genus_vec, subfamily_vec)

  result <- mapped_growth_form
  result[is_gram & !is_bamb]  <- "graminoid"
  result[is_gram & is_bamb]   <- "bamboo"
  result
}
