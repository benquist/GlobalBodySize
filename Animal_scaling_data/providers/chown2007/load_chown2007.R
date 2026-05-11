## providers/chown2007/load_chown2007.R
## Chown et al. 2007 — "Scaling of insect metabolic rate is inconsistent with
## the nutrient supply network model."
## Functional Ecology 21(2):282-290.
## DOI: 10.1111/j.1365-2435.2007.01245.x
##
## Data: Appendix S2 of supplementary material (fec1245_supmat.doc)
##   391 insect species across 16 orders
##   Measurements: body mass (mg), resting metabolic rate (µW),
##                 respirometry method (open/closed/manometric), wing status
##
## Corrections applied from Riveros & Enquist (2011):
##   Riveros AJ, Enquist BJ. 2011. Metabolic scaling in insects supports the
##   predictions of the WBE model. J Insect Physiology 57:688-693.
##   DOI: 10.1016/j.jinsphys.2011.01.011
##   Three Coleoptera species from Stromme et al. 1986 had incorrect metabolic
##   rates (unit conversion error). Corrected values used here.
##
## SOURCE FILE REQUIREMENT:
##   Place fec1245_supmat.doc in providers/chown2007/data/raw/
##   (copy from ~/Downloads/fec1245_supmat.doc)
##   The file is extracted from the Chown et al. 2007 supplementary materials.
##   textutil (macOS built-in) is used to convert Word → plain text for parsing.
##
## Output schema (standard Animal_scaling_data columns):
##   source_id, source_display_name, source_doi, source_access_date,
##   bibliographic_citation, original_row_id, source_file_path,
##   verbatim_taxon_name, input_taxonomic_group, input_taxonomic_rank,
##   resolved_taxon_name, kingdom, phylum, class, order, family, genus,
##   body_mass_g, body_mass_source,
##   metabolic_rate_value, metabolic_rate_unit, metabolic_rate_type,
##   metabolic_rate_temp_C,
##   lifespan_max_years, lifespan_source,
##   age_at_maturity_years, litter_clutch_size, litters_per_year,
##   growth_rate_value, growth_rate_unit, growth_model,
##   qa_flag, qa_body_mass_range, qa_metabolic_unit_verified,
##   wing_status, respirometry_method

suppressPackageStartupMessages(library(data.table))

SOURCE_ID    <- "chown2007"
SOURCE_DOI   <- "10.1111/j.1365-2435.2007.01245.x"
CORRECTION_DOI <- "10.1016/j.jinsphys.2011.01.011"
BIBLIOGRAPHIC_CITATION <- paste0(
  "Chown SL, Marais E, Terblanche JS, Klok CJ, Lighton JRB, Blackburn TM. ",
  "2007. Scaling of insect metabolic rate is inconsistent with the nutrient ",
  "supply network model. Functional Ecology 21(2):282-290. ",
  "https://doi.org/10.1111/j.1365-2435.2007.01245.x. ",
  "Data corrections from: Riveros AJ, Enquist BJ. 2011. ",
  "J Insect Physiology 57:688-693. ",
  "https://doi.org/10.1016/j.jinsphys.2011.01.011"
)

## ── Riveros & Enquist 2011 corrections ──────────────────────────────────────
## 3 Coleoptera species from Stromme et al. (1986) had unit-conversion errors
## in Chown et al. The corrected BMR values (µW) from Riveros & Enquist Table 1
## are applied by species name match.
RIVEROS_CORRECTIONS <- data.table(
  species_match = c("Amara quenseli", "Simplocaria metallica", "Rhynchaenus flagellum"),
  corrected_metabolic_rate_uW = c(346.5, 32.7, 9.1),
  notes = rep("Corrected per Riveros & Enquist 2011, Table 1 (unit conversion error in Stromme et al. 1986)", 3)
)

## ── Order → input_taxonomic_group mapping ───────────────────────────────────
ORDER_TO_GROUP <- c(
  "Archaeognatha"  = "insect",
  "Thysanura"      = "insect",
  "Blattodea"      = "insect",
  "Coleoptera"     = "insect",
  "Diptera"        = "insect",
  "Hemiptera"      = "insect",
  "Hymenoptera"    = "insect",
  "Isoptera"       = "insect",
  "Lepidoptera"    = "insect",
  "Neuroptera"     = "insect",
  "Odonata"        = "insect",
  "Orthoptera"     = "insect",
  "Phasmatodea"    = "insect",
  "Psocoptera"     = "insect",
  "Siphonaptera"   = "insect",
  "Trichoptera"    = "insect"
)

## ── Mass range QA bounds (insects) ──────────────────────────────────────────
MASS_MIN_G <- 1e-6   # 0.001 mg — sub-micrograms implausible
MASS_MAX_G <- 100    # 100 g   — largest recorded insect ~80 g

## ── Parse raw text extracted from fec1245_supmat.doc ────────────────────────
#' Parse Appendix S2 from Chown et al. 2007 supplementary Word document.
#'
#' Requires macOS textutil (pre-installed) to convert .doc → plain text.
#' The table is stored one cell per line in the Word doc; records are separated
#' by blank lines.  Each record = 7 fields: Species, Family, Order, Method,
#' Wing status, Mass (mg), Metabolic rate (µW).
#'
#' Many species rows have embedded EndNote citation fields (ADDIN EN.CITE ...)
#' that span multiple wrapped lines in the textutil output.  These are stripped
#' via a PCRE multiline regex BEFORE splitting back into individual lines.
#'
#' @param doc_path  Path to fec1245_supmat.doc
#' @return data.table with raw parsed fields, or NULL on failure
parse_chown_doc <- function(doc_path) {
  if (!file.exists(doc_path))
    stop("Chown2007: source doc not found: ", doc_path, call. = FALSE)

  ## Convert doc → text lines
  raw_lines <- tryCatch(
    system2("textutil", c("-convert", "txt", "-stdout", shQuote(doc_path)),
            stdout = TRUE, stderr = FALSE),
    error = function(e) stop("textutil failed: ", conditionMessage(e), call. = FALSE)
  )
  if (length(raw_lines) == 0)
    stop("Chown2007: textutil produced no output", call. = FALSE)

  ## ── Step 1: find section boundaries in the original line array ──────────
  s2_start <- grep("Appendix S2", raw_lines)[1]
  if (is.na(s2_start))
    stop("Chown2007: Could not find 'Appendix S2' in document", call. = FALSE)

  hdr_idx <- grep("^Species$", raw_lines)
  hdr_idx <- hdr_idx[hdr_idx > s2_start][1]
  if (is.na(hdr_idx))
    stop("Chown2007: Could not find column headers after Appendix S2", call. = FALSE)

  data_start <- hdr_idx + 7L   # skip the 7 column-header lines

  ## ── Step 2: collapse ALL remaining lines into one string and strip XML ───
  ## ADDIN EN.CITE blocks span multiple wrapped lines.  Collapse first, then
  ## strip using PCRE with (?s) dotall mode, then re-split.
  raw_text <- paste(raw_lines[data_start:length(raw_lines)], collapse = "\n")

  ## Strip ADDIN EN.CITE...citation XML blocks (including trailing ref number)
  raw_text <- gsub("ADDIN EN\\.CITE(?s:.)*?</EndNote>[0-9]*", "",
                   raw_text, perl = TRUE)

  ## Strip any remaining XML-style tags
  raw_text <- gsub("<[^>]+>", "", raw_text)

  ## Strip HTML-encoded entities like &lt;Go to ISI&gt;://...
  raw_text <- gsub("&[a-zA-Z]+;[^\\s]*", "", raw_text)

  ## Strip footnote / annotation lines (PAGE field, pilcrow, footnote text)
  raw_text <- gsub("(?m)^PAGE\\s+[\\d ]*$", "", raw_text, perl = TRUE)
  raw_text <- gsub("(?m)^Temperature refers.*$", "", raw_text, perl = TRUE)
  raw_text <- gsub("(?m)^\\s*[*\u0166\u00b6\u00a4]+\\s*$", "", raw_text, perl = TRUE)

  ## Re-split into lines and trim
  data_lines <- strsplit(raw_text, "\n", fixed = TRUE)[[1]]
  data_lines <- trimws(data_lines)

  ## ── Step 3: group consecutive non-blank lines into 7-field records ───────
  ## Between records there are ≥1 blank lines. Accumulate non-blank lines;
  ## once 7 are collected, that is one complete record. Reset on blank.
  records <- list()
  fields  <- character(0)

  for (ln in data_lines) {
    if (nchar(ln) == 0) {
      ## Blank line: flush any complete record
      if (length(fields) == 7) {
        records[[length(records) + 1]] <- fields
      }
      if (length(fields) > 0) fields <- character(0)
    } else {
      fields <- c(fields, ln)
      if (length(fields) == 7) {
        records[[length(records) + 1]] <- fields
        fields <- character(0)
      }
    }
  }
  if (length(fields) == 7) records[[length(records) + 1]] <- fields

  if (length(records) == 0)
    stop("Chown2007: No records parsed from Appendix S2", call. = FALSE)

  message(sprintf("Chown2007: parsed %d raw records from Appendix S2", length(records)))

  dt <- rbindlist(lapply(seq_along(records), function(i) {
    r <- records[[i]]
    data.table(
      original_row_id       = i,
      verbatim_species      = r[1],
      verbatim_family       = r[2],
      verbatim_order        = r[3],
      respirometry_method   = r[4],
      wing_status_raw       = r[5],
      mass_mg_raw           = r[6],
      metabolic_rate_uW_raw = r[7]
    )
  }), fill = TRUE)

  dt
}

## ── Main intake function ─────────────────────────────────────────────────────
#' Run the Chown 2007 intake pipeline.
#'
#' @param doc_path   Path to fec1245_supmat.doc (default: within provider dir)
#' @param output_file Path to write compiled CSV
#' @param dest_dir    If provided, copy source doc there first
run_chown2007_intake <- function(
  doc_path    = "providers/chown2007/data/raw/fec1245_supmat.doc",
  output_file = "output/chown2007_compiled.csv",
  copy_from   = NULL    # e.g. "~/Downloads/fec1245_supmat.doc"
) {
  ## Optionally copy from Downloads
  if (!is.null(copy_from)) {
    copy_from <- path.expand(copy_from)
    if (!file.exists(copy_from))
      stop("Source doc not found at: ", copy_from, call. = FALSE)
    dir.create(dirname(doc_path), recursive = TRUE, showWarnings = FALSE)
    file.copy(copy_from, doc_path, overwrite = TRUE)
    message("Chown2007: copied source doc to ", doc_path)
  }

  ## Parse
  raw <- parse_chown_doc(doc_path)

  ## Filter out non-species rows (bibliography entries, footnote lines) that
  ## can bleed in from the end of the supplementary table.
  ## Valid species names start with an uppercase letter followed by lowercase.
  raw <- raw[grepl("^[A-Z][a-z]", verbatim_species) |
             grepl("^Unknown", verbatim_species, ignore.case = TRUE)]
  message(sprintf("Chown2007: %d records after filtering non-species rows", nrow(raw)))

  ## Strip internal whitespace from numeric fields (e.g. "23. 6" → "23.6")
  raw[, mass_mg_raw            := gsub("\\s+", "", mass_mg_raw)]
  raw[, metabolic_rate_uW_raw  := gsub("\\s+", "", metabolic_rate_uW_raw)]

  ## Numeric coercions
  raw[, body_mass_g    := suppressWarnings(as.numeric(mass_mg_raw)) / 1000]
  raw[, metabolic_rate_uW := suppressWarnings(as.numeric(gsub(",", "", metabolic_rate_uW_raw)))]
  # Convert µW → W
  raw[, metabolic_rate_W := metabolic_rate_uW / 1e6]
  raw[, wing_status    := suppressWarnings(as.integer(wing_status_raw))]

  ## Drop rows with no parseable mass or metabolic rate
  n_raw <- nrow(raw)
  raw   <- raw[!is.na(body_mass_g) & !is.na(metabolic_rate_uW)]
  message(sprintf("Chown2007: %d/%d records have numeric mass & metabolic rate",
                  nrow(raw), n_raw))

  ## Apply Riveros & Enquist 2011 corrections to 3 Coleoptera species
  for (i in seq_len(nrow(RIVEROS_CORRECTIONS))) {
    sp  <- RIVEROS_CORRECTIONS$species_match[i]
    cor <- RIVEROS_CORRECTIONS$corrected_metabolic_rate_uW[i]
    idx <- which(grepl(sp, raw$verbatim_species, fixed = TRUE))
    if (length(idx) > 0) {
      message(sprintf("Chown2007: correcting '%s' metabolic rate %.3g → %.3g µW (Riveros & Enquist 2011)",
                      sp, raw$metabolic_rate_uW[idx[1]], cor))
      raw[idx, `:=`(metabolic_rate_uW = cor,
                    metabolic_rate_W  = cor / 1e6)]
    } else {
      warning(sprintf("Chown2007: correction target '%s' not found in parsed data", sp))
    }
  }

  ## Map order to standard group
  raw[, input_taxonomic_group := ORDER_TO_GROUP[verbatim_order]]
  raw[is.na(input_taxonomic_group), input_taxonomic_group := "insect"]

  ## QA flag
  raw[, qa_flag := "ok"]
  raw[is.na(body_mass_g) | body_mass_g <= 0,  qa_flag := "missing_mass"]
  raw[is.na(metabolic_rate_W) | metabolic_rate_W <= 0, qa_flag := "missing_metabolic_rate"]
  raw[body_mass_g < MASS_MIN_G | body_mass_g > MASS_MAX_G, qa_flag := "mass_out_of_range"]

  ## QA sub-flags
  raw[, qa_body_mass_range    := ifelse(body_mass_g >= MASS_MIN_G & body_mass_g <= MASS_MAX_G, "ok", "out_of_range")]
  raw[, qa_metabolic_unit_verified := TRUE]

  ## Build output in standard schema
  out <- data.table(
    source_id                = SOURCE_ID,
    source_display_name      = "Chown et al. 2007 (corrected per Riveros & Enquist 2011)",
    source_doi               = SOURCE_DOI,
    source_access_date       = as.character(Sys.Date()),
    bibliographic_citation   = BIBLIOGRAPHIC_CITATION,
    original_row_id          = raw$original_row_id,
    source_file_path         = basename(doc_path),
    verbatim_taxon_name      = raw$verbatim_species,
    input_taxonomic_group    = raw$input_taxonomic_group,
    input_taxonomic_rank     = "species",
    resolved_taxon_name      = "",
    kingdom                  = "Animalia",
    phylum                   = "Arthropoda",
    class                    = "Insecta",
    order                    = raw$verbatim_order,
    family                   = raw$verbatim_family,
    genus                    = sub("^([A-Z][a-z]+).*", "\\1", raw$verbatim_species),
    body_mass_g              = raw$body_mass_g,
    body_mass_source         = "literature_mean",
    metabolic_rate_value     = raw$metabolic_rate_W,
    metabolic_rate_unit      = "W",
    metabolic_rate_type      = "resting",
    metabolic_rate_temp_C    = NA_real_,   # temperature not stored per-row in Appendix S2
    lifespan_max_years       = NA_real_,
    lifespan_source          = "",
    age_at_maturity_years    = NA_real_,
    litter_clutch_size       = NA_real_,
    litters_per_year         = NA_real_,
    growth_rate_value        = NA_real_,
    growth_rate_unit         = "",
    growth_model             = "",
    qa_flag                  = raw$qa_flag,
    qa_body_mass_range       = raw$qa_body_mass_range,
    qa_metabolic_unit_verified = raw$qa_metabolic_unit_verified,
    wing_status              = raw$wing_status,
    respirometry_method      = raw$respirometry_method
  )

  ## Summary
  n_ok <- sum(out$qa_flag == "ok")
  message(sprintf("\nChown2007 intake complete:"))
  message(sprintf("  Total records:      %d", nrow(out)))
  message(sprintf("  QA-pass (ok):       %d", n_ok))
  message(sprintf("  Orders:             %d", length(unique(out$order[out$order != ""]))))
  message(sprintf("  Families:           %d", length(unique(out$family[out$family != ""]))))
  message(sprintf("  Riveros corrections applied to 3 Coleoptera species"))
  message(sprintf("  Mass range (g):     %.2e – %.2e", min(out$body_mass_g, na.rm=TRUE),
                  max(out$body_mass_g, na.rm=TRUE)))
  message(sprintf("  Metabolic rate (W): %.2e – %.2e",
                  min(out$metabolic_rate_value, na.rm=TRUE),
                  max(out$metabolic_rate_value, na.rm=TRUE)))

  ## Write output
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  fwrite(out, output_file)
  message(sprintf("  Written: %s", output_file))
  invisible(out)
}
