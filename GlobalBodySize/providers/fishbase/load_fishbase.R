## GlobalBodySize/providers/fishbase/load_fishbase.R
## Intake script for FishBase body mass via rfishbase
## Froese R, Pauly D (Eds). FishBase. www.fishbase.org (cite year accessed)
##
## CRITICAL NOTE (merow-ecology advisory):
## FishBase does NOT provide direct body mass measurements for most species.
## Mass is DERIVED from length-weight (L-W) relationships: W = a * L^b
## This makes FishBase body mass LW_modeled, NOT directly measured.
## The parameters a, b, and n MUST be stored alongside any computed mass.
## This is a Tier B source (requires QA; propagate LW uncertainty).
##
## R package: rfishbase (CRAN)
## Install: install.packages("rfishbase")
##
## Output: data.frame conforming to GlobalBodySize schema

FISHBASE_SOURCE_ID   <- "fishbase_rfishbase"
FISHBASE_DISPLAY     <- "FishBase via rfishbase"
FISHBASE_CITATION    <- "Froese R, Pauly D (Eds). FishBase. World Wide Web electronic publication. www.fishbase.org. Accessed [date]. rfishbase: Boettiger C, et al."
FISHBASE_DOI         <- NA_character_  # UNVERIFIED — rfishbase package DOI

## ---- Extract length-weight parameters and compute reference mass -----------
##
## Strategy:
## 1. For each species, pull all L-W relationships from rfishbase::length_weight()
## 2. Select the "best" relationship (largest n, or geometric mean of all)
## 3. Compute mass at a reference length (e.g., maximum TL from species table)
## 4. Store a, b, n, reference_length alongside computed mass
##
## rfishbase API confirmed 2026-05-10:
##   rfishbase::load_taxa()  -> cols: SpecCode, Species, Genus, Family, Order, Class, SuperClass
##   rfishbase::species(species_list, fields=c("Species","Weight","Length"))
##     Weight = max recorded weight in grams (direct; ~3,100/36,000 species have it)
##     Length = max total length in cm (TL; ~29,000 species have it)
##   rfishbase::length_weight(species_list)
##     -> cols: Species, a, b, Type (TL/SL/FL), Number, LengthMin, LengthMax, ...

run_fishbase_intake <- function(species_list = NULL,
                                output_file = "output/fishbase_compiled.csv",
                                max_species = NULL) {

  if (!requireNamespace("rfishbase", quietly = TRUE)) {
    stop("Package 'rfishbase' required. Install with: install.packages('rfishbase')", call. = FALSE)
  }

  ## Get full species list via load_taxa() — returns proper binomials
  if (is.null(species_list)) {
    message("Loading FishBase species list via load_taxa()...")
    taxa <- rfishbase::load_taxa()
    species_list <- taxa$Species
    message("Total FishBase species: ", length(species_list))
    if (!is.null(max_species)) species_list <- species_list[seq_len(min(max_species, length(species_list)))]
    message("Running intake for: ", length(species_list), " species")
  }

  ## Step 1: Fetch direct weight (and max length) from species table
  ## Weight = max recorded weight in grams (~3,100 species have it — use as priority path)
  message("Fetching direct weight and max length from species table...")
  sp_direct <- tryCatch(
    rfishbase::species(species_list = species_list,
                       fields = c("Species", "Weight", "Length")),
    error = function(e) {
      message("rfishbase::species() direct weight fetch failed: ", conditionMessage(e))
      NULL
    }
  )

  ## Step 2: Fetch L-W parameters for species missing direct weight
  message("Fetching L-W parameters for ", length(species_list), " species...")

  ## Fetch length-weight relationships
  lw <- tryCatch(
    rfishbase::length_weight(species_list = species_list),
    error = function(e) {
      stop("rfishbase::length_weight() failed: ", conditionMessage(e), call. = FALSE)
    }
  )

  ## Fetch species table for max total length (for L-W mass computation)
  sp_maxlen <- sp_direct  ## reuse — already contains Length column

  ## Filter to Total Length (TL) equations only — mixing TL/SL/FL before geometric mean
  ## produces inconsistent reference units. Fallback to all equations with a warning
  ## when Type column is absent (older rfishbase versions).
  if (!is.null(lw) && "Type" %in% names(lw)) {
    n_before_tl <- nrow(lw)
    lw_tl <- lw[!is.na(lw$Type) & lw$Type == "TL", ]
    if (nrow(lw_tl) > 0) {
      lw <- lw_tl
      message(sprintf("FishBase: retained %d/%d LW equations with Type==TL",
                      nrow(lw), n_before_tl))
    } else {
      warning("FishBase: no Type==TL equations found — using all length types (UNVERIFIED)")
    }
  } else {
    warning("FishBase: 'Type' column absent from rfishbase::length_weight() — using all equations without length-type filter (UNVERIFIED)")
  }

  ## UNVERIFIED column names — confirm with rfishbase documentation
  ## Expected: Species, a, b, CoeffDetermination, Number, LengthMin, LengthMax, Type
  lw_agg <- aggregate(
    cbind(a = lw$a, b = lw$b),  ## UNVERIFIED column names
    by = list(Species = lw$Species),
    FUN = function(x) exp(mean(log(x), na.rm = TRUE))
  )

  ## lw_n counts the number of published LW *equations* (not individual fish measured).
  ## This is stored in lw_relationship_n — not mass_n — to avoid misinterpretation.
  lw_agg$lw_relationship_n <- as.integer(table(lw$Species)[lw_agg$Species])

  ## Merge per-species max length; fall back to 30 cm for species with no LMax
  if (!is.null(sp_maxlen) && "Length" %in% names(sp_maxlen)) {
    lw_agg <- merge(lw_agg, sp_maxlen[, c("Species", "Length")],
                    by = "Species", all.x = TRUE)
    lw_agg$reference_length_cm      <- ifelse(!is.na(lw_agg$Length), lw_agg$Length, 30)
    lw_agg$reference_length_source  <- ifelse(!is.na(lw_agg$Length), "MaxTL_rfishbase", "30cm_fallback")
  } else {
    lw_agg$reference_length_cm     <- 30
    lw_agg$reference_length_source <- "30cm_fallback"
  }

  ## Compute mass at per-species reference length: W = a * L^b (W in grams, L in cm)
  lw_agg$mass_lw_g <- lw_agg$a * (lw_agg$reference_length_cm ^ lw_agg$b)

  ## Merge direct weight into lw_agg
  if (!is.null(sp_direct) && "Weight" %in% names(sp_direct)) {
    lw_agg <- merge(lw_agg, sp_direct[, c("Species", "Weight")],
                    by = "Species", all.x = TRUE)
  } else {
    lw_agg$Weight <- NA_real_
  }

  ## Priority: direct weight (recorded max weight in grams) > LW-modeled
  ## Direct weight is marked as measured_max, LW-modeled as LW_modeled
  lw_agg$mass_g          <- ifelse(!is.na(lw_agg$Weight) & lw_agg$Weight > 0,
                                   lw_agg$Weight, lw_agg$mass_lw_g)
  lw_agg$mass_type_final <- ifelse(!is.na(lw_agg$Weight) & lw_agg$Weight > 0,
                                   "wet", "LW_modeled")
  lw_agg$method_final    <- ifelse(!is.na(lw_agg$Weight) & lw_agg$Weight > 0,
                                   "recorded_max_weight", "LW_equation")
  lw_agg$qa_note_final   <- ifelse(!is.na(lw_agg$Weight) & lw_agg$Weight > 0,
    "direct_max_weight_from_rfishbase_species()",
    sprintf("LW_modeled: a=%s b=%s lw_eq_n=%s at L=%gcm (%s)",
            round(lw_agg$a, 6), round(lw_agg$b, 4),
            lw_agg$lw_relationship_n,
            lw_agg$reference_length_cm,
            lw_agg$reference_length_source))

  n_direct <- sum(!is.na(lw_agg$Weight) & lw_agg$Weight > 0, na.rm = TRUE)
  message(sprintf("FishBase: %d species with direct weight, %d with LW-modeled weight",
                  n_direct, sum(lw_agg$mass_type_final == "LW_modeled", na.rm = TRUE)))

  ## Map to schema
  out <- data.frame(
    source_id              = FISHBASE_SOURCE_ID,
    source_display_name    = FISHBASE_DISPLAY,
    source_doi             = FISHBASE_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = FISHBASE_CITATION,
    dataset_id             = FISHBASE_SOURCE_ID,
    original_row_id        = seq_len(nrow(lw_agg)),
    source_file_path       = "rfishbase_api",

    verbatim_taxon_name    = lw_agg$Species,
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "fish",
    input_taxonomic_rank   = "species",

    mass_g                 = lw_agg$mass_g,
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = NA_integer_,

    mass_type              = lw_agg$mass_type_final,
    measurement_method     = lw_agg$method_final,
    life_stage             = "unknown",
    sex                    = "unknown",

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = NA_character_,

    year_measured          = NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "Literature",

    mass_confidence        = "medium",
    qa_note                = lw_agg$qa_note_final,
    qa_status              = NA_character_,

    stringsAsFactors = FALSE
  )

  out <- out[!is.na(out$mass_g) & out$mass_g > 0, ]
  message("FishBase: ", nrow(out), " species with mass -> ", output_file)

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("FishBase compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
