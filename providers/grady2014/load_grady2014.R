## providers/grady2014/load_grady2014.R
## Grady et al. 2014 — Evidence for mesothermy in dinosaurs
##
## Reference:
##   Grady JM, Enquist BJ, Dettweiler-Robinson E, Wright NA, Smith FA (2014)
##   Evidence for mesothermy in dinosaurs. Science 344:1268-1272.
##   DOI: 10.1126/science.1253143
##
## Data source:
##   Table S1 of the supplementary materials PDF. No open data deposit exists.
##   Data were extracted from PDF by pdftools (see data/raw/README.md) and
##   parsed to CSV at: providers/grady2014/data/raw/grady2014_table_s1.csv
##
## Coverage: 381 species/taxa spanning 11 taxonomic groups:
##   Crocodylia (12), Mesozoic Dinosaurs (21), Placental Mammals (153),
##   Marsupials (19), Monotremata (2), Neornithes altricial (35),
##   Neornithes precocial (28), Sharks (22), Squamata (26),
##   Teleost Fish (61), Testudines (2).
##
## Dataset scope:
##   PRIMARY USE — growth rates (Gmax g/d) and metabolic rates (W) with body mass
##   for scaling law analyses. Intended for Animal_scaling_data project.
##   SECONDARY USE — final adult mass (final_adult_mass_g) added to GlobalBodySize
##   as an independent body mass estimate for cross-taxon comparisons.
##
## Columns in raw CSV (grady2014_table_s1.csv):
##   verbatim_taxon_name  — species name (φ and * markers stripped; flags separate)
##   taxonomic_group      — group from Table S1 section header
##   is_extinct           — TRUE if marked φ in table
##   is_mesotherm         — TRUE if marked * in table (elevated growth like endotherms)
##   metabolic_mass_g     — body mass at which BMR was measured (not final adult mass)
##   metabolic_rate_W     — basal/standard metabolic rate in watts
##   ta_c                 — ambient temperature (°C) at which BMR was measured
##   final_adult_mass_g   — final adult mass from growth curve asymptote (= mass_g here)
##   gmax_g_per_day       — maximum growth rate (g/day)
##   r2_growth_curve      — r² of growth curve fit
##   n_growth_obs         — number of mass-at-age data points
##   curve_only           — TRUE if r2/n from curve fit only (not equation)
##   equation_only        — TRUE if r2/n from equation only (no curve)
##
## OUTPUTS:
##   output/grady2014_mass_compiled.csv   — GlobalBodySize-compatible mass rows
##   output/grady2014_growth_compiled.csv — full growth + metabolic rate data

suppressPackageStartupMessages(library(data.table))

## ---- Constants --------------------------------------------------------------

GRADY2014_SOURCE_ID    <- "grady_etal_2014"
GRADY2014_DISPLAY      <- "Grady et al. 2014 (Science 344:1268)"
GRADY2014_DOI          <- "10.1126/science.1253143"
GRADY2014_CITATION     <- paste0(
  "Grady JM, Enquist BJ, Dettweiler-Robinson E, Wright NA, Smith FA (2014) ",
  "Evidence for mesothermy in dinosaurs. Science 344:1268-1272. ",
  "https://doi.org/10.1126/science.1253143"
)
GRADY2014_DATA_NOTE    <- paste0(
  "Table S1 extracted from supplementary PDF by pdftools; ",
  "no open data deposit available as of 2026-05-11"
)
GRADY2014_ACCESS_DATE  <- "2026-05-11"

## Map Grady 2014 Table S1 section headers to GlobalBodySize input_taxonomic_group
GROUP_MAP <- c(
  "Crocodylia"             = "reptile",
  "Mesozoic Dinosaurs"     = "reptile",
  "Placental Mammals"      = "mammal",
  "Marsupials"             = "mammal",
  "Monotremata"            = "mammal",
  "Neornithes (altricial)" = "bird",
  "Neornithes (precocial)" = "bird",
  "Sharks"                 = "fish",
  "Squamata"               = "reptile",
  "Teleost Fish"           = "fish",
  "Testudines"             = "reptile"
)

## ---- Main function ----------------------------------------------------------

run_grady2014_intake <- function(
    raw_file     = "providers/grady2014/data/raw/grady2014_table_s1.csv",
    output_mass  = "output/grady2014_mass_compiled.csv",
    output_growth = "output/grady2014_growth_compiled.csv"
) {
  message("=== Grady et al. 2014 Intake ===")
  message("Citation: ", GRADY2014_CITATION)

  ## 1. Load -------------------------------------------------------------------
  if (!file.exists(raw_file)) {
    stop(
      "Raw data file not found: ", raw_file, "\n",
      "Run the PDF extraction script first — see providers/grady2014/data/raw/README.md",
      call. = FALSE
    )
  }
  dt <- fread(raw_file, encoding = "UTF-8",
               na.strings = c("", "NA", "N/A", "na", "NULL"))
  message(sprintf("Loaded %d rows from %s", nrow(dt), raw_file))

  ## 2. Map taxonomic groups ---------------------------------------------------
  dt[, input_taxonomic_group := GROUP_MAP[taxonomic_group]]
  n_unmapped <- sum(is.na(dt$input_taxonomic_group))
  if (n_unmapped > 0) {
    warning(sprintf("%d rows have unmapped taxonomic_group", n_unmapped))
    message("Unmapped groups: ", paste(unique(dt$taxonomic_group[is.na(dt$input_taxonomic_group)]), collapse = ", "))
  }

  ## 3. Quality flags ----------------------------------------------------------
  dt[, data_quality_flag := "ok"]
  dt[is.na(final_adult_mass_g),  data_quality_flag := "no_mass"]
  dt[is.na(gmax_g_per_day),       data_quality_flag := paste0(data_quality_flag, ";no_gmax")]
  dt[is_extinct == TRUE,          data_quality_flag := paste0(data_quality_flag, ";extinct")]

  ## 4. Build GlobalBodySize mass output ---------------------------------------
  ## Only extant species with a measured final adult mass
  mass_dt <- dt[!is.na(final_adult_mass_g) & is_extinct == FALSE, .(
    source_id            = GRADY2014_SOURCE_ID,
    source_display_name  = GRADY2014_DISPLAY,
    verbatim_taxon_name,
    input_taxonomic_group,
    mass_g               = final_adult_mass_g,
    mass_type            = "wet",
    mass_measurement_type = "literature_asymptote",
    data_quality_flag,
    data_notes           = GRADY2014_DATA_NOTE
  )]

  message(sprintf("Mass output: %d rows (%d extant with mass)", nrow(mass_dt), nrow(mass_dt)))

  dir.create(dirname(output_mass), showWarnings = FALSE, recursive = TRUE)
  fwrite(mass_dt, output_mass)
  message("Written: ", output_mass)

  ## 5. Build full growth + metabolic output -----------------------------------
  ## All rows, including extinct
  growth_dt <- dt[, .(
    source_id            = GRADY2014_SOURCE_ID,
    source_display_name  = GRADY2014_DISPLAY,
    source_doi           = GRADY2014_DOI,
    source_citation      = GRADY2014_CITATION,
    source_data_note     = GRADY2014_DATA_NOTE,
    source_access_date   = GRADY2014_ACCESS_DATE,
    verbatim_taxon_name,
    taxonomic_group_grady = taxonomic_group,
    input_taxonomic_group,
    is_extinct,
    is_mesotherm,
    metabolic_mass_g,
    metabolic_rate_W,
    ta_c,
    final_adult_mass_g,
    gmax_g_per_day,
    r2_growth_curve,
    n_growth_obs,
    curve_only,
    equation_only,
    data_quality_flag
  )]

  dir.create(dirname(output_growth), showWarnings = FALSE, recursive = TRUE)
  fwrite(growth_dt, output_growth)
  message(sprintf("Written: %s (%d rows)", output_growth, nrow(growth_dt)))

  ## 6. Summary ----------------------------------------------------------------
  message("\n--- Summary ---")
  message(sprintf("Total rows: %d", nrow(dt)))
  message(sprintf("  Extant:     %d", sum(!dt$is_extinct)))
  message(sprintf("  Extinct:    %d", sum(dt$is_extinct)))
  message(sprintf("  Mesotherms: %d", sum(dt$is_mesotherm)))
  message(sprintf("  Has metabolic rate: %d", sum(!is.na(dt$metabolic_rate_W))))
  message(sprintf("  Has final mass:     %d", sum(!is.na(dt$final_adult_mass_g))))
  message("\nBreakdown by group:")
  print(dt[, .N, by = .(taxonomic_group, input_taxonomic_group)][order(-N)])

  invisible(list(mass = mass_dt, growth = growth_dt))
}

## ---- Run if called directly -------------------------------------------------
if (!interactive()) {
  run_grady2014_intake()
}
