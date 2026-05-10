## GlobalBodySize/R/taxon_reconciliation.R
## Taxonomic reconciliation helpers for GlobalBodySize
## Uses GBIF Backbone as cross-group super-backbone via rgbif::name_backbone()
## Group-specific backbones: MDD (mammals), BirdLife (birds), FishBase (fish),
##   AmphibiaWeb (amphibians), The Reptile Database (reptiles), GBIF (insects), WCVP (plants)
##
## NOTE: This module handles the GBIF backbone layer only.
##       Group-specific backbone queries are in providers/*/reconcile_*.R
##
## PACKAGE DEPENDENCIES: rgbif, data.table
## Verify availability: install.packages(c("rgbif", "data.table"))

## ---- GBIF backbone query (batched) ------------------------------------------

## Retrieve the GBIF Backbone modification date as a version string.
## Uses the stable GBIF dataset API with the backbone datasetKey.
get_gbif_backbone_version <- function() {
  backbone_key <- "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"
  tryCatch({
    tmp <- tempfile(fileext = ".json")
    ret <- system(
      sprintf('curl -s -f "https://api.gbif.org/v1/dataset/%s" -o "%s"',
              backbone_key, tmp),
      ignore.stderr = TRUE
    )
    if (ret != 0 || !file.exists(tmp) || file.size(tmp) == 0) return(NA_character_)
    info <- jsonlite::fromJSON(tmp, simplifyVector = TRUE)
    unlink(tmp)
    pub_date <- info$pubDate %||% info$modified %||% NA_character_
    paste0("GBIF_Backbone_", substr(pub_date, 1, 10))
  }, error = function(e) {
    warning("Could not retrieve GBIF backbone version: ", conditionMessage(e))
    paste0("GBIF_Backbone_accessed_", format(Sys.Date(), "%Y-%m-%d"))
  })
}

## Normalize a taxon name for API query: strip qualifiers, normalize whitespace.
normalize_taxon_name <- function(x) {
  ## Strip nomenclatural qualifiers (cf., aff., nr., sp., spp., var., subsp., agg.)
  x <- gsub("\\b(cf|aff|nr|sp|spp|var|subsp|agg)\\.?\\s*", "", x, perl = TRUE)
  ## Normalize whitespace
  trimws(gsub("\\s+", " ", x))
}

## Query GBIF backbone for a vector of taxon names
## Returns a data.frame with match results and provenance fields
gbif_reconcile_names <- function(names_vec,
                                 kingdom_filter = NULL,
                                 batch_size = 200,
                                 cache_file = NULL,
                                 verbose = TRUE) {

  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop("Package 'rgbif' is required. Install with: install.packages('rgbif')", call. = FALSE)
  }

  ## Load cache if provided
  cached <- if (!is.null(cache_file) && file.exists(cache_file)) {
    data.table::fread(cache_file, data.table = FALSE)
  } else {
    NULL
  }

  to_query <- if (!is.null(cached)) {
    setdiff(names_vec, cached$input_name_verbatim)
  } else {
    names_vec
  }

  if (!length(to_query)) {
    if (verbose) message("All names found in cache.")
    return(cached)
  }

  if (verbose) message("Querying GBIF backbone for ", length(to_query), " names...")

  ## Retrieve backbone version once per session
  backbone_ver <- get_gbif_backbone_version()
  if (verbose) message("GBIF Backbone version: ", backbone_ver)

  batches <- split(to_query, ceiling(seq_along(to_query) / batch_size))
  results <- lapply(seq_along(batches), function(i) {
    batch <- batches[[i]]
    if (verbose) message("  Batch ", i, "/", length(batches), " (", length(batch), " names)")

    rows <- lapply(batch, function(nm) {
      nm_normalized <- normalize_taxon_name(nm)
      tryCatch({
        res <- rgbif::name_backbone(
          name    = nm_normalized,
          kingdom = kingdom_filter,
          strict  = FALSE
        )
        is_synonym <- !is.null(res$status) &&
          res$status %in% c("SYNONYM", "HOMOTYPIC_SYNONYM",
                            "HETEROTYPIC_SYNONYM", "MISAPPLIED")
        ## Correct accepted_usage_key: do NOT fall back to usageKey for synonyms
        ## that lack an acceptedUsageKey — store NA instead of the synonym's own key
        acc_key <- if (!is.null(res$acceptedUsageKey) && length(res$acceptedUsageKey) > 0) {
          res$acceptedUsageKey
        } else if (!is_synonym) {
          res$usageKey %||% NA_integer_
        } else {
          NA_integer_
        }
        mc <- classify_match(
          res$matchType %||% NA_character_,
          res$confidence %||% NA_integer_,
          res$status %||% NA_character_
        )
        data.frame(
          input_name_verbatim    = nm,
          input_name_normalized  = nm_normalized,
          matched_name           = res$canonicalName      %||% NA_character_,
          matched_authorship     = res$authorship         %||% NA_character_,
          matched_rank           = res$rank               %||% NA_character_,
          gbif_usage_key         = res$usageKey           %||% NA_integer_,
          matched_status         = res$status             %||% NA_character_,
          ## accepted_name: use canonicalName of accepted concept, not res$species
          accepted_name          = if (is_synonym)
                                     res$species %||% NA_character_
                                   else
                                     res$canonicalName %||% NA_character_,
          accepted_usage_key     = acc_key,
          kingdom                = res$kingdom            %||% NA_character_,
          phylum                 = res$phylum             %||% NA_character_,
          class                  = res$class              %||% NA_character_,
          order                  = res$order              %||% NA_character_,
          family                 = res$family             %||% NA_character_,
          genus                  = res$genus              %||% NA_character_,
          match_type             = res$matchType          %||% NA_character_,
          confidence             = res$confidence         %||% NA_integer_,
          match_method           = mc$match_method,
          match_confidence       = mc$match_confidence,
          synonym_type           = mc$synonym_type,
          decision_note          = mc$decision_note,
          primary_backbone       = "GBIF_Backbone",
          backbone_version       = backbone_ver,
          query_timestamp_utc    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
          stringsAsFactors = FALSE
        )
      }, error = function(e) {
        data.frame(input_name_verbatim = nm, input_name_normalized = nm_normalized,
                   matched_name = NA_character_, matched_authorship = NA_character_,
                   matched_rank = NA_character_, gbif_usage_key = NA_integer_,
                   matched_status = "error", accepted_name = NA_character_,
                   accepted_usage_key = NA_integer_, kingdom = NA_character_,
                   phylum = NA_character_, class = NA_character_,
                   order = NA_character_, family = NA_character_,
                   genus = NA_character_, match_type = "error",
                   confidence = NA_integer_, match_method = "no_match",
                   match_confidence = "unassessable", synonym_type = NA_character_,
                   decision_note = paste0("API error: ", conditionMessage(e)),
                   primary_backbone = "GBIF_Backbone",
                   backbone_version = backbone_ver,
                   query_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                   stringsAsFactors = FALSE)
      })
    })
    Sys.sleep(0.1)  # be polite to GBIF API
    do.call(rbind, rows)
  })

  new_results <- do.call(rbind, results)

  ## Combine with cache
  combined <- if (!is.null(cached)) rbind(cached, new_results) else new_results

  ## Save cache
  if (!is.null(cache_file)) {
    data.table::fwrite(combined, cache_file)
    if (verbose) message("Cache saved: ", cache_file)
  }

  combined
}

## ---- Derive match_method and match_confidence from GBIF response -----------

classify_match <- function(match_type, confidence, matched_status) {
  if (!requireNamespace("dplyr", quietly = TRUE))
    stop("Package 'dplyr' is required for classify_match()", call. = FALSE)

  ## Synonym status takes precedence over match_type:
  ## GBIF can return matchType=EXACT with status=SYNONYM simultaneously,
  ## meaning the verbatim name was found exactly as a synonym entry.
  ## These must be classified as 'synonym', not 'exact', to trigger correct handling.
  is_synonym <- !is.na(matched_status) &
    matched_status %in% c("SYNONYM", "HOMOTYPIC_SYNONYM",
                          "HETEROTYPIC_SYNONYM", "MISAPPLIED")

  method <- dplyr::case_when(
    is_synonym                        ~ "synonym",
    is.na(match_type)                 ~ "no_match",
    match_type == "EXACT"             ~ "exact",
    match_type == "FUZZY"             ~ "fuzzy",
    match_type == "HIGHERRANK"        ~ "canonical",
    TRUE                              ~ "no_match"
  )

  ## synonym_type from GBIF status
  syn_type <- dplyr::case_when(
    matched_status == "HOMOTYPIC_SYNONYM"  ~ "homotypic",
    matched_status == "HETEROTYPIC_SYNONYM" ~ "heterotypic",
    matched_status == "MISAPPLIED"         ~ "misapplied",
    matched_status == "SYNONYM"            ~ "unknown",
    TRUE                                   ~ NA_character_
  )

  conf <- dplyr::case_when(
    !is.na(confidence) & confidence >= 95 & method == "exact"    ~ "high",
    !is.na(confidence) & confidence >= 80 & method != "no_match" ~ "medium",
    !is.na(confidence) & confidence >= 60                        ~ "low",
    TRUE                                                         ~ "unassessable"
  )

  note <- dplyr::case_when(
    method == "synonym" ~ paste0("Synonym hit: status=", matched_status),
    method == "fuzzy"   ~ paste0("Fuzzy match: matchType=FUZZY, confidence=", confidence),
    method == "canonical" ~ paste0("Higher-rank match: matchType=HIGHERRANK"),
    method == "no_match" ~ "No backbone match found",
    TRUE                ~ NA_character_
  )

  list(match_method = method, match_confidence = conf,
       synonym_type = syn_type, decision_note = note)
}

## ---- Cross-group collision detection ----------------------------------------
## Flag cases where same GBIF usageKey appears for names from >1 taxonomic group
## These are potential homonym collisions

detect_cross_group_collisions <- function(reconciled_df) {
  if (!all(c("gbif_usage_key", "input_taxonomic_group") %in% names(reconciled_df))) {
    stop("reconciled_df must have gbif_usage_key and input_taxonomic_group columns")
  }
  key_group <- unique(reconciled_df[, c("gbif_usage_key", "input_taxonomic_group")])
  key_group <- key_group[!is.na(key_group$gbif_usage_key), ]
  collision_keys <- names(which(table(key_group$gbif_usage_key) > 1))
  reconciled_df$cross_group_collision_flag <- reconciled_df$gbif_usage_key %in% collision_keys
  reconciled_df
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
