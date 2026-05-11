## providers/animaltraits/load_animaltraits.R
## AnimalTraits — curated terrestrial animal trait database (body mass, metabolic
## rate, brain size) across a wide taxonomic range including vertebrates and
## invertebrates (insects, arachnids, crustaceans, myriapods, annelids, molluscs)
##
## Reference:
##   Herberstein ME, McLean DJ, Lowe E, Wolff JO, Khan MK, Smith K, ... Carthey AJR.
##   2022. AnimalTraits — a curated animal trait database for body mass, metabolic
##   rate and brain size. Scientific Data 9(1):265.
##   DOI: 10.1038/s41597-022-01364-9
##
## Data hosted on Zenodo (public domain waiver — no restrictions):
##   DOI: 10.5281/zenodo.6468938
##   CSV: https://zenodo.org/record/6468938/files/observations.csv?download=1
##
## Body mass column: "body mass" (in kg — converted to grams here)
## Schema: 43 columns; phylum, class, order, family, genus, species, sex,
##         sampleSizeValue, inTextReference, fullReference, body mass, units, min/max
##
## Coverage (from live inspection 2026-05-11):
##   3,580 observation rows; 2,856 with body mass; 1,830 unique species with mass
##   Mammalia 622 spp | Aves 760 spp | Insecta 296 spp | Reptilia 72 spp
##   Arachnida 65 spp | Amphibia 10 spp | Malacostraca 2 spp + other invertebrates
##
## NOTE: All body mass values in the source are in kilograms.
##       This script converts to grams for GlobalBodySize schema compatibility.
##       Vertebrate species (Mammalia, Aves, Reptilia, Amphibia) will overlap with
##       existing providers; duplicate detection runs in merge_tier1.R after GBIF
##       reconciliation. Invertebrate classes are net-new to GlobalBodySize.

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
})

## ---- Constants --------------------------------------------------------------

ANIMALTRAITS_ZENODO_ID  <- "6468938"
ANIMALTRAITS_CSV_URL    <- paste0(
  "https://zenodo.org/record/", ANIMALTRAITS_ZENODO_ID,
  "/files/observations.csv?download=1"
)
ANIMALTRAITS_SOURCE_ID  <- "animaltraits_herberstein2022"
ANIMALTRAITS_DISPLAY    <- "AnimalTraits (Herberstein et al. 2022)"
ANIMALTRAITS_DOI        <- "10.1038/s41597-022-01364-9"
ANIMALTRAITS_DATA_DOI   <- "10.5281/zenodo.6468938"
ANIMALTRAITS_CITATION   <- paste0(
  "Herberstein ME, McLean DJ, Lowe E, Wolff JO, Khan MK, Smith K, ",
  "Buzatto BA, Eldridge MDB, Endler J, Evans JP, Gaskett AC, Holwell GI, ",
  "Johnson SL, Joseph L, Latty T, Lighton JRB, Madin JS, Phillips BL, ",
  "Pintor LM, Popple LW, Pryke SR, Redhead JW, Rodgers E, Rojas B, ",
  "Sato CF, Tatarnic N, Wapstra E, Whiting MJ, Wong BBM, Yee MS, ",
  "Zeil J, Carthey AJR. 2022. ",
  "AnimalTraits - a curated animal trait database for body mass, metabolic rate ",
  "and brain size. Scientific Data 9(1):265. ",
  "https://doi.org/10.1038/s41597-022-01364-9. ",
  "Data: https://doi.org/10.5281/zenodo.6468938"
)

## Map GBIF/AnimalTraits class names to GlobalBodySize input_taxonomic_group.
## Vertebrate groups overlap with existing providers but are retained for
## cross-provider validation. Invertebrate groups are net-new for Phase 2.
CLASS_TO_GROUP <- c(
  "Mammalia"      = "mammal",
  "Aves"          = "bird",
  "Reptilia"      = "reptile",
  "Amphibia"      = "amphibian",
  ## Net-new invertebrate groups
  "Insecta"       = "insect",
  "Arachnida"     = "arachnid",
  "Malacostraca"  = "crustacean",
  "Chilopoda"     = "myriapod",
  "Diplopoda"     = "myriapod",
  "Clitellata"    = "annelid",
  "Polychaeta"    = "annelid",
  "Gastropoda"    = "gastropod",
  "Bivalvia"      = "bivalve"
)

## ---- Download helper --------------------------------------------------------

.animaltraits_download <- function(dest_dir, overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "animaltraits_observations.csv")

  if (file.exists(dest_file) && !overwrite) {
    message("AnimalTraits: using cached file at ", dest_file)
    return(dest_file)
  }

  message("AnimalTraits: downloading from Zenodo DOI ", ANIMALTRAITS_DATA_DOI, " ...")
  rc <- tryCatch(
    {
      download.file(
        url      = ANIMALTRAITS_CSV_URL,
        destfile = dest_file,
        mode     = "wb",
        quiet    = FALSE
      )
      0L
    },
    error   = function(e) { warning("Download failed: ", conditionMessage(e)); 1L },
    warning = function(w) { warning("Download warning: ", conditionMessage(w)); 1L }
  )

  if (rc != 0 || !file.exists(dest_file) || file.size(dest_file) < 1000) {
    stop("AnimalTraits: download failed or file too small. Check network and URL.",
         call. = FALSE)
  }

  message(sprintf("AnimalTraits: downloaded %.1f MB -> %s",
                  file.size(dest_file) / 1e6, dest_file))
  dest_file
}

## ---- Main function ----------------------------------------------------------
##
## @param dest_dir          Directory for raw downloaded file
## @param output_file       Path for the compiled output CSV
## @param overwrite_download  Re-download even if raw file exists
## @param include_vertebrates  Include Mammalia/Aves/Reptilia/Amphibia rows
##                             (TRUE = include for cross-provider validation;
##                              FALSE = invertebrates only, avoids redundancy)
## @param min_mass_g        Drop rows below this threshold (g); default 1e-6 (1 µg)
## @param max_mass_g        Drop rows above this threshold (g); default 1e8 (100 tonnes)

run_animaltraits_intake <- function(
    dest_dir            = "providers/animaltraits/data/raw",
    output_file         = "output/animaltraits_compiled.csv",
    overwrite_download  = FALSE,
    include_vertebrates = TRUE,
    min_mass_g          = 1e-6,
    max_mass_g          = 1e8
) {
  message("=== AnimalTraits Intake ===")
  message("Citation: ", ANIMALTRAITS_CITATION)

  ## 1. Download ---------------------------------------------------------------
  raw_file <- .animaltraits_download(dest_dir, overwrite = overwrite_download)

  ## 2. Load -------------------------------------------------------------------
  ## UTF-8 encoded per documentation
  dt <- data.table::fread(
    raw_file,
    encoding = "UTF-8",
    na.strings = c("", "NA", "N/A", "na")
  )
  message(sprintf("AnimalTraits: %d observation rows loaded", nrow(dt)))

  ## 3. Filter to rows with a body mass value ----------------------------------
  ## Column is "body mass" (kg); "body mass - units" should always be "kg"
  mass_col <- "body mass"
  if (!mass_col %in% names(dt)) {
    stop("Column 'body mass' not found. Schema may have changed. ",
         "Available: ", paste(names(dt), collapse = ", "), call. = FALSE)
  }

  dt_mass <- dt[!is.na(get(mass_col))]
  message(sprintf("AnimalTraits: %d rows with body mass value", nrow(dt_mass)))

  ## Verify units
  if ("body mass - units" %in% names(dt_mass)) {
    units_tab <- table(dt_mass[["body mass - units"]], useNA = "always")
    message("Body mass units breakdown: ",
            paste(names(units_tab), units_tab, sep = "=", collapse = "; "))
    non_kg <- dt_mass[["body mass - units"]][!is.na(dt_mass[["body mass - units"]]) &
                                               dt_mass[["body mass - units"]] != "kg"]
    if (length(non_kg) > 0) {
      warning("AnimalTraits: ", length(non_kg),
              " rows have non-kg mass units — inspect before merging: ",
              paste(unique(non_kg), collapse = ", "))
    }
  }

  ## 4. Convert kg -> g --------------------------------------------------------
  dt_mass[, mass_g := get(mass_col) * 1000]

  ## Plausibility filter
  n_before <- nrow(dt_mass)
  dt_mass <- dt_mass[mass_g >= min_mass_g & mass_g <= max_mass_g]
  n_dropped <- n_before - nrow(dt_mass)
  if (n_dropped > 0) {
    message(sprintf("AnimalTraits: %d rows dropped outside plausibility bounds [%.2e, %.2e] g",
                    n_dropped, min_mass_g, max_mass_g))
  }

  ## 5. Map class to input_taxonomic_group -------------------------------------
  dt_mass[, input_taxonomic_group := CLASS_TO_GROUP[class]]
  dt_mass[is.na(input_taxonomic_group), input_taxonomic_group := tolower(trimws(class))]

  ## Report group breakdown
  grp_tab <- sort(table(dt_mass$input_taxonomic_group), decreasing = TRUE)
  message("Group breakdown:\n",
          paste(sprintf("  %s: %d rows", names(grp_tab), as.integer(grp_tab)),
                collapse = "\n"))

  ## Optionally exclude vertebrate classes (they overlap with existing providers)
  if (!include_vertebrates) {
    vertebrate_groups <- c("mammal", "bird", "reptile", "amphibian")
    dt_mass <- dt_mass[!input_taxonomic_group %in% vertebrate_groups]
    message(sprintf(
      "AnimalTraits: vertebrates excluded; %d rows (invertebrates only) retained",
      nrow(dt_mass)
    ))
  }

  ## 6. Build species binomial from genus + species columns --------------------
  ## "species" column contains only the specificEpithet in some rows;
  ## full binomial may be in "species" directly or needs genus + specificEpithet
  dt_mass[, verbatim_name := {
    sp <- trimws(species)
    ## If species already contains a space, it's likely a full binomial
    ifelse(grepl(" ", sp), sp,
           paste(trimws(genus), sp))
  }]
  dt_mass[, verbatim_name := trimws(verbatim_name)]

  ## 7. Build reference string -------------------------------------------------
  ## inTextReference is short citation; fullReference is full bibliographic string
  dt_mass[, row_citation := ifelse(
    !is.na(fullReference) & nchar(trimws(fullReference)) > 5,
    trimws(fullReference),
    trimws(inTextReference)
  )]

  ## 8. Assemble output schema -------------------------------------------------
  out <- data.frame(
    source_id              = ANIMALTRAITS_SOURCE_ID,
    source_display_name    = ANIMALTRAITS_DISPLAY,
    source_doi             = ANIMALTRAITS_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = ANIMALTRAITS_CITATION,
    dataset_id             = ANIMALTRAITS_SOURCE_ID,
    original_row_id        = seq_len(nrow(dt_mass)),
    source_file_path       = raw_file,

    verbatim_taxon_name    = dt_mass$verbatim_name,
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = dt_mass$input_taxonomic_group,
    input_taxonomic_rank   = "species",

    mass_g                 = dt_mass$mass_g,
    mass_g_min             = dt_mass[["body mass - minimum"]] * 1000,
    mass_g_max             = dt_mass[["body mass - maximum"]] * 1000,
    mass_se                = NA_real_,
    mass_n                 = suppressWarnings(as.integer(dt_mass$sampleSizeValue)),

    mass_type              = "wet",
    measurement_method     = ifelse(
      !is.na(dt_mass[["body mass - method"]]) & nchar(trimws(dt_mass[["body mass - method"]])) > 0,
      trimws(dt_mass[["body mass - method"]]),
      "literature_compiled"
    ),
    life_stage             = NA_character_,
    sex                    = tolower(trimws(dt_mass$sex)),

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = NA_character_,

    year_measured          = suppressWarnings(as.integer(dt_mass$publicationYear)),
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "Literature",

    ## Class-level taxonomy for routing and QA
    source_phylum          = dt_mass$phylum,
    source_class           = dt_mass$class,
    source_order           = dt_mass$order,
    source_family          = dt_mass$family,

    mass_confidence        = "moderate",
    qa_note                = paste0(
      "converted from kg; class=", dt_mass$class,
      "; ref=", dt_mass$inTextReference
    ),
    qa_status              = NA_character_,

    ## Source-level comments for future auditing
    mass_comments          = dt_mass[["body mass - comments"]],
    primary_citation       = dt_mass$row_citation,

    stringsAsFactors = FALSE
  )

  ## 9. Summary and write ------------------------------------------------------
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)

  message(sprintf("AnimalTraits compiled: %d rows -> %s", nrow(out), output_file))
  message(sprintf("  Unique verbatim species: %d",
                  length(unique(out$verbatim_taxon_name[!is.na(out$verbatim_taxon_name)]))))

  grp_final <- sort(table(out$input_taxonomic_group), decreasing = TRUE)
  message("  Final group counts:")
  for (g in names(grp_final)) {
    message(sprintf("    %s: %d rows", g, grp_final[[g]]))
  }

  invisible(out)
}

## Standalone runner
if (!interactive() && !exists("ANIMALTRAITS_SOURCED_AS_LIBRARY")) {
  run_animaltraits_intake(
    dest_dir   = "providers/animaltraits/data/raw",
    output_file = "output/animaltraits_compiled.csv"
  )
}
