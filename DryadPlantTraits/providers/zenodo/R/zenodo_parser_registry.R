zenodo_apply_parser_registry <- function(df, provenance = list(), dictionary = NULL) {
  dataset_id <- provenance$dryad_dataset_doi
  if (is.null(dataset_id) || !length(dataset_id) || is.na(dataset_id)) {
    dataset_id <- NA_character_
  }

  registry <- list(
    "zenodo:19816125" = zenodo_parser_19816125
  )

  parser <- registry[[as.character(dataset_id)]]
  if (is.null(parser)) return(NULL)

  parsed <- tryCatch(
    parser(df, provenance = provenance, dictionary = dictionary),
    error = function(e) NULL
  )

  if (is.data.frame(parsed) && nrow(parsed) > 0L) {
    return(parsed)
  }

  NULL
}

zenodo_parser_19816125 <- function(df, provenance = list(), dictionary = NULL) {
  if (!is.data.frame(df) || !nrow(df)) return(NULL)

  required_signal <- c("P50", "TLP", "Ks", "pl_LA", "pl_huber_value", "gs")
  if (!"pl_species" %in% names(df)) return(NULL)
  if (!any(required_signal %in% names(df))) return(NULL)

  df2 <- df
  if (!"species" %in% names(df2) && "pl_species" %in% names(df2)) {
    df2$species <- df2$pl_species
  } else if ("species" %in% names(df2) && "pl_species" %in% names(df2)) {
    species_blank <- is.na(df2$species) | !nzchar(trimws(as.character(df2$species)))
    pl_species_has_value <- !is.na(df2$pl_species) & nzchar(trimws(as.character(df2$pl_species)))
    fill_idx <- species_blank & pl_species_has_value
    if (any(fill_idx)) {
      df2$species[fill_idx] <- df2$pl_species[fill_idx]
    }
  }

  rename_map <- c(
    pl_LA = "leaf_area",
    pl_huber_value = "huber_value",
    pl_SLA = "specific_leaf_area",
    gs = "stomatal_conductance",
    P50 = "p50",
    TLP = "turgor_loss_point",
    Ks = "stem_hydraulic_conductivity"
  )

  for (from_name in names(rename_map)) {
    to_name <- rename_map[[from_name]]
    if (from_name %in% names(df2) && !to_name %in% names(df2)) {
      names(df2)[names(df2) == from_name] <- to_name
    } else if (from_name %in% names(df2) && to_name %in% names(df2)) {
      to_blank <- is.na(df2[[to_name]]) | !nzchar(trimws(as.character(df2[[to_name]])))
      from_has_value <- !is.na(df2[[from_name]]) & nzchar(trimws(as.character(df2[[from_name]])))
      fill_idx <- to_blank & from_has_value
      if (any(fill_idx)) {
        df2[[to_name]][fill_idx] <- df2[[from_name]][fill_idx]
      }
    }
  }

  dryad_standardize_records(df2, provenance = provenance, dictionary = dictionary)
}
