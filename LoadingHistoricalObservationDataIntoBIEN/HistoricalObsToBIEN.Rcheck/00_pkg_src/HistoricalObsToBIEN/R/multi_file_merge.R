read_uploaded_csv_list <- function(file_input) {
  if (is.null(file_input) || nrow(file_input) == 0) {
    return(list())
  }

  out <- list()
  for (i in seq_len(nrow(file_input))) {
    path <- file_input$datapath[i]
    name <- file_input$name[i]
    df <- read_historical_csv(path)
    df$.source_file <- name
    out[[name]] <- df
  }

  out
}

first_non_empty <- function(x) {
  if (is.factor(x)) {
    x <- as.character(x)
  }
  non_missing <- x[!is.na(x) & trimws(as.character(x)) != ""]
  if (length(non_missing) == 0) {
    return(NA)
  }
  non_missing[1]
}

collapse_by_key <- function(df, key_col) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }
  if (!key_col %in% names(df)) {
    stop("Key column not found: ", key_col)
  }

  key_vals <- as.character(df[[key_col]])
  split_idx <- split(seq_len(nrow(df)), key_vals)

  rows <- lapply(split_idx, function(idx) {
    chunk <- df[idx, , drop = FALSE]
    out_row <- lapply(chunk, first_non_empty)
    as.data.frame(out_row, stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

coalesce_duplicate_suffix_columns <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }

  nm <- names(df)
  suffix_match <- grepl("\\.meta$", nm)
  meta_cols <- nm[suffix_match]

  for (meta_col in meta_cols) {
    base_col <- sub("\\.meta$", "", meta_col)
    if (!base_col %in% names(df)) {
      names(df)[names(df) == meta_col] <- base_col
      next
    }

    base_vals <- df[[base_col]]
    meta_vals <- df[[meta_col]]

    if (is.factor(base_vals)) base_vals <- as.character(base_vals)
    if (is.factor(meta_vals)) meta_vals <- as.character(meta_vals)

    use_meta <- is.na(base_vals) | trimws(as.character(base_vals)) == ""
    base_vals[use_meta] <- meta_vals[use_meta]
    df[[base_col]] <- base_vals
    df[[meta_col]] <- NULL
  }

  df
}

merge_uploaded_streams <- function(data_list, primary_file, primary_key, metadata_files, metadata_keys) {
  if (length(data_list) == 0) {
    stop("No uploaded files available.")
  }
  if (is.null(primary_file) || !nzchar(primary_file) || !primary_file %in% names(data_list)) {
    stop("Select a valid primary file.")
  }

  primary_df <- data_list[[primary_file]]
  if (is.null(primary_key) || !nzchar(primary_key) || !primary_key %in% names(primary_df)) {
    stop("Select a valid primary key column.")
  }

  merged <- primary_df

  for (f in metadata_files) {
    if (!f %in% names(data_list)) {
      next
    }

    meta_key <- metadata_keys[[f]]
    if (is.null(meta_key) || !nzchar(meta_key)) {
      next
    }

    meta_df <- data_list[[f]]
    if (!meta_key %in% names(meta_df)) {
      next
    }

    meta_collapsed <- collapse_by_key(meta_df, meta_key)
    merged <- merge(
      merged,
      meta_collapsed,
      by.x = primary_key,
      by.y = meta_key,
      all.x = TRUE,
      sort = FALSE,
      suffixes = c("", ".meta")
    )

    merged <- coalesce_duplicate_suffix_columns(merged)
  }

  merged
}

normalize_join_key <- function(x) {
  y <- as.character(x)
  y <- trimws(y)
  y[is.na(y) | y == ""] <- NA
  y
}

classify_join_cardinality <- function(primary_dup_keys, metadata_dup_keys) {
  if (primary_dup_keys > 0 && metadata_dup_keys > 0) {
    return("many-to-many")
  }
  if (primary_dup_keys > 0 && metadata_dup_keys == 0) {
    return("many-to-one")
  }
  if (primary_dup_keys == 0 && metadata_dup_keys > 0) {
    return("one-to-many")
  }
  "one-to-one"
}

audit_join_quality <- function(data_list, primary_file, primary_key, metadata_files, metadata_keys) {
  if (length(data_list) == 0) {
    stop("No uploaded files available.")
  }
  if (!primary_file %in% names(data_list)) {
    stop("Select a valid primary file.")
  }

  primary_df <- data_list[[primary_file]]
  if (!primary_key %in% names(primary_df)) {
    stop("Select a valid primary key column.")
  }

  p_key <- normalize_join_key(primary_df[[primary_key]])
  p_valid <- !is.na(p_key)
  p_freq <- table(p_key[p_valid], useNA = "no")

  rows <- lapply(metadata_files, function(f) {
    if (!f %in% names(data_list)) {
      return(NULL)
    }
    meta_key <- metadata_keys[[f]]
    if (is.null(meta_key) || !nzchar(meta_key) || !meta_key %in% names(data_list[[f]])) {
      return(NULL)
    }

    meta_df <- data_list[[f]]
    m_key <- normalize_join_key(meta_df[[meta_key]])
    m_valid <- !is.na(m_key)
    m_freq <- table(m_key[m_valid], useNA = "no")

    common_keys <- intersect(names(p_freq), names(m_freq))
    matched_primary_rows <- if (length(common_keys) == 0) 0 else sum(p_freq[common_keys])
    unmatched_primary_rows <- sum(p_valid) - matched_primary_rows
    matched_metadata_rows <- if (length(common_keys) == 0) 0 else sum(m_freq[common_keys])
    unmatched_metadata_rows <- sum(m_valid) - matched_metadata_rows

    p_dup <- sum(p_freq > 1)
    m_dup <- sum(m_freq > 1)
    cardinality <- classify_join_cardinality(p_dup, m_dup)
    duplicate_metadata_collapse <- m_dup > 0

    expected_rows <- sum(p_freq)
    if (length(common_keys) > 0) {
      expected_rows <- expected_rows + sum((p_freq[common_keys] * m_freq[common_keys]) - p_freq[common_keys])
    }

    risk_multiplier <- if (sum(p_valid) == 0) NA_real_ else expected_rows / sum(p_valid)
    severity <- if (identical(cardinality, "many-to-many")) {
      "BLOCK"
    } else if (identical(cardinality, "one-to-many") || unmatched_primary_rows > 0) {
      "WARN"
    } else {
      "PASS"
    }

    detail <- if (identical(cardinality, "many-to-many")) {
      "Many-to-many join risk detected. Resolve duplicate keys before building handoff tables."
    } else if (duplicate_metadata_collapse) {
      "Duplicate metadata keys detected. Metadata rows will be collapsed by key using the first non-empty value in each column. Review for conflicts before export."
    } else if (unmatched_primary_rows > 0) {
      "Some primary rows do not match metadata and will retain missing joined values. Review before export."
    } else {
      "Join audit passed current checks. Manual review is still required for biological and geographic plausibility."
    }

    data.frame(
      metadata_file = f,
      primary_key = primary_key,
      metadata_key = meta_key,
      join_cardinality = cardinality,
      severity = severity,
      duplicate_metadata_collapse = duplicate_metadata_collapse,
      primary_rows_with_key = sum(p_valid),
      metadata_rows_with_key = sum(m_valid),
      matched_primary_rows = matched_primary_rows,
      unmatched_primary_rows = unmatched_primary_rows,
      matched_metadata_rows = matched_metadata_rows,
      unmatched_metadata_rows = unmatched_metadata_rows,
      primary_duplicate_keys = p_dup,
      metadata_duplicate_keys = m_dup,
      shared_unique_keys = length(common_keys),
      expected_rows_after_join = expected_rows,
      expected_row_multiplier = round(risk_multiplier, 3),
      detail = detail,
      stringsAsFactors = FALSE
    )
  })

  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) {
    return(data.frame(
      metadata_file = character(0),
      primary_key = character(0),
      metadata_key = character(0),
      join_cardinality = character(0),
      severity = character(0),
      duplicate_metadata_collapse = logical(0),
      primary_rows_with_key = integer(0),
      metadata_rows_with_key = integer(0),
      matched_primary_rows = integer(0),
      unmatched_primary_rows = integer(0),
      matched_metadata_rows = integer(0),
      unmatched_metadata_rows = integer(0),
      primary_duplicate_keys = integer(0),
      metadata_duplicate_keys = integer(0),
      shared_unique_keys = integer(0),
      expected_rows_after_join = integer(0),
      expected_row_multiplier = numeric(0),
      detail = character(0),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, rows)
}

find_duplicate_metadata_conflicts <- function(data_list, metadata_files, metadata_keys) {
  if (length(data_list) == 0) {
    return(data.frame(
      metadata_file = character(0),
      metadata_key = character(0),
      key_value = character(0),
      conflict_column = character(0),
      conflicting_values = character(0),
      stringsAsFactors = FALSE
    ))
  }

  conflicts <- list()

  for (f in metadata_files) {
    if (!f %in% names(data_list)) {
      next
    }

    meta_key <- metadata_keys[[f]]
    if (is.null(meta_key) || !nzchar(meta_key)) {
      next
    }

    meta_df <- data_list[[f]]
    if (!meta_key %in% names(meta_df) || nrow(meta_df) == 0) {
      next
    }

    key_vals <- normalize_join_key(meta_df[[meta_key]])
    key_tab <- table(key_vals[!is.na(key_vals)], useNA = "no")
    dup_keys <- names(key_tab[key_tab > 1])

    if (length(dup_keys) == 0) {
      next
    }

    for (k in dup_keys) {
      idx <- which(key_vals == k)
      chunk <- meta_df[idx, , drop = FALSE]
      cols <- setdiff(names(chunk), meta_key)

      for (col in cols) {
        vals <- as.character(chunk[[col]])
        vals <- trimws(vals)
        vals <- vals[!is.na(vals) & vals != ""]
        uniq <- unique(vals)

        if (length(uniq) > 1) {
          conflicts[[length(conflicts) + 1]] <- data.frame(
            metadata_file = f,
            metadata_key = meta_key,
            key_value = k,
            conflict_column = col,
            conflicting_values = paste(uniq, collapse = " | "),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  if (length(conflicts) == 0) {
    return(data.frame(
      metadata_file = character(0),
      metadata_key = character(0),
      key_value = character(0),
      conflict_column = character(0),
      conflicting_values = character(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- do.call(rbind, conflicts)
  rownames(out) <- NULL
  out
}
