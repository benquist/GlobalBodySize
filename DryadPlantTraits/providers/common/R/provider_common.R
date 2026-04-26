`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

provider_parse_named_args <- function(args) {
  values <- list()
  if (!length(args)) {
    return(values)
  }

  for (arg in args) {
    if (!startsWith(arg, "--")) {
      next
    }
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }

  values
}

provider_find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") {
    return(cwd)
  }
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") {
    return(dirname(cwd))
  }
  if (basename(cwd) %in% c("try", "fred", "leda") && grepl("providers$", dirname(cwd))) {
    return(dirname(dirname(cwd)))
  }
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) {
    return(probe)
  }
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

provider_trim_to_na <- function(x) {
  out <- trimws(as.character(x))
  out[out == ""] <- NA_character_
  out
}

provider_is_supported_tabular_path <- function(path) {
  lower_path <- tolower(path)
  any(endsWith(lower_path, c(".csv", ".tsv", ".txt", ".tab", ".xlsx", ".xls")))
}

provider_is_supported_archive_path <- function(path) {
  lower_path <- tolower(path)
  any(endsWith(lower_path, c(".zip", ".tar", ".tar.gz", ".tgz", ".gz")))
}

provider_infer_file_support <- function(file_path) {
  file_path <- ifelse(is.na(file_path), "", as.character(file_path))
  data.frame(
    file_supported_tabular = vapply(file_path, provider_is_supported_tabular_path, logical(1)),
    file_supported_container = vapply(file_path, provider_is_supported_archive_path, logical(1)),
    stringsAsFactors = FALSE
  )
}

provider_alias_key <- function(x) {
  tolower(gsub("[^a-z0-9]+", "", x))
}

provider_find_column <- function(df, aliases) {
  if (!nrow(df) && !ncol(df)) {
    return(NULL)
  }

  keys <- provider_alias_key(names(df))
  for (alias in aliases) {
    idx <- which(keys == provider_alias_key(alias))
    if (length(idx)) {
      return(names(df)[idx[[1]]])
    }
  }
  NULL
}

provider_extract_column <- function(df, aliases, default = NA_character_) {
  column_name <- provider_find_column(df, aliases)
  if (is.null(column_name)) {
    return(rep(default, nrow(df)))
  }
  as.character(df[[column_name]])
}

provider_to_numeric <- function(x, default = NA_real_) {
  x <- provider_trim_to_na(x)
  out <- suppressWarnings(as.numeric(x))
  out[is.na(out)] <- default
  out
}

provider_to_logical <- function(x, default = TRUE) {
  x <- provider_trim_to_na(x)
  lowered <- tolower(x)
  out <- rep(default, length(lowered))
  out[lowered %in% c("true", "t", "1", "yes", "y")] <- TRUE
  out[lowered %in% c("false", "f", "0", "no", "n")] <- FALSE
  out
}

provider_dataset_schema <- function(n = 0L) {
  data.frame(
    source_provider = rep(NA_character_, n),
    provider_dataset_id = rep(NA_character_, n),
    query_term = rep(NA_character_, n),
    title = rep(NA_character_, n),
    authors = rep(NA_character_, n),
    abstract = rep(NA_character_, n),
    source_subjects = rep(NA_character_, n),
    field_of_science = rep(NA_character_, n),
    storage_size = rep(NA_real_, n),
    candidate_score = rep(NA_real_, n),
    candidate_keep = rep(TRUE, n),
    candidate_rationale = rep(NA_character_, n),
    stringsAsFactors = FALSE
  )
}

provider_file_schema <- function(n = 0L) {
  data.frame(
    source_provider = rep(NA_character_, n),
    provider_dataset_id = rep(NA_character_, n),
    provider_file_id = rep(NA_character_, n),
    file_path = rep(NA_character_, n),
    file_size = rep(NA_real_, n),
    mime_type = rep(NA_character_, n),
    file_status = rep(NA_character_, n),
    download_href = rep(NA_character_, n),
    candidate_score = rep(NA_real_, n),
    candidate_keep = rep(TRUE, n),
    query_term = rep(NA_character_, n),
    source_title = rep(NA_character_, n),
    source_authors = rep(NA_character_, n),
    source_subjects = rep(NA_character_, n),
    source_abstract = rep(NA_character_, n),
    file_supported_tabular = rep(FALSE, n),
    file_supported_container = rep(FALSE, n),
    stringsAsFactors = FALSE
  )
}

provider_complete_dataset_schema <- function(df) {
  schema <- provider_dataset_schema(0)
  missing_cols <- setdiff(names(schema), names(df))
  if (length(missing_cols)) {
    for (col in missing_cols) {
      df[[col]] <- schema[[col]]
    }
  }
  df <- df[, names(schema), drop = FALSE]
  df$candidate_keep <- provider_to_logical(df$candidate_keep, default = TRUE)
  df$candidate_score <- provider_to_numeric(df$candidate_score)
  df
}

provider_complete_file_schema <- function(df) {
  schema <- provider_file_schema(0)
  missing_cols <- setdiff(names(schema), names(df))
  if (length(missing_cols)) {
    for (col in missing_cols) {
      df[[col]] <- schema[[col]]
    }
  }
  df <- df[, names(schema), drop = FALSE]
  df$candidate_keep <- provider_to_logical(df$candidate_keep, default = TRUE)
  df$candidate_score <- provider_to_numeric(df$candidate_score)
  df$file_supported_tabular <- provider_to_logical(df$file_supported_tabular, default = FALSE)
  df$file_supported_container <- provider_to_logical(df$file_supported_container, default = FALSE)
  df
}

provider_read_manifest <- function(path) {
  if (!file.exists(path)) {
    stop("Manifest file does not exist: ", path, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("csv", "tsv", "txt", "tab")) {
    sep <- if (ext %in% c("tsv", "tab")) "\t" else if (ext == "txt") "" else ","
    if (sep == "") {
      # Keep behavior simple for .txt: infer from first line.
      first_line <- readLines(path, n = 1L, warn = FALSE)
      sep <- if (length(first_line) && grepl("\t", first_line[[1]], fixed = TRUE)) "\t" else ","
    }
    return(utils::read.table(
      path,
      header = TRUE,
      sep = sep,
      quote = '"',
      comment.char = "",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE
    ))
  }

  if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop(
        "Manifest appears to be Excel format, but package 'readxl' is not installed. ",
        "Install it with: install.packages('readxl')",
        call. = FALSE
      )
    }
    return(as.data.frame(readxl::read_excel(path), stringsAsFactors = FALSE, check.names = FALSE))
  }

  stop("Unsupported manifest file extension: .", ext, call. = FALSE)
}

provider_build_dataset_candidates <- function(df, provider_name, candidate_score_default = 0.5, candidate_keep_default = TRUE) {
  if (!nrow(df)) {
    return(provider_dataset_schema(0))
  }

  dataset_id <- provider_extract_column(df, c(
    "provider_dataset_id", "dataset_id", "datasetid", "study_id", "studyid", "id", "doi", "dryad_dataset_doi"
  ))
  dataset_id <- provider_trim_to_na(dataset_id)
  missing_id <- is.na(dataset_id)
  if (any(missing_id)) {
    dataset_id[missing_id] <- sprintf("%s_dataset_%s", provider_name, seq_len(sum(missing_id)))
  }

  out <- data.frame(
    source_provider = rep(provider_name, nrow(df)),
    provider_dataset_id = dataset_id,
    query_term = provider_trim_to_na(provider_extract_column(df, c("query_term", "search_term", "query", "keyword"))),
    title = provider_trim_to_na(provider_extract_column(df, c("title", "dataset_title", "study_title", "name"))),
    authors = provider_trim_to_na(provider_extract_column(df, c("authors", "creator", "creators", "author_list"))),
    abstract = provider_trim_to_na(provider_extract_column(df, c("abstract", "description", "summary"))),
    source_subjects = provider_trim_to_na(provider_extract_column(df, c("subjects", "subject", "keywords", "tags"))),
    field_of_science = provider_trim_to_na(provider_extract_column(df, c("field_of_science", "field", "discipline"))),
    storage_size = provider_to_numeric(provider_extract_column(df, c("storage_size", "dataset_size", "size_bytes"))),
    candidate_score = provider_to_numeric(
      provider_extract_column(df, c("candidate_score", "score", "relevance_score")),
      default = candidate_score_default
    ),
    candidate_keep = provider_to_logical(
      provider_extract_column(df, c("candidate_keep", "keep", "include")),
      default = candidate_keep_default
    ),
    candidate_rationale = provider_trim_to_na(provider_extract_column(df, c("candidate_rationale", "rationale", "notes"))),
    stringsAsFactors = FALSE
  )

  out <- provider_complete_dataset_schema(out)

  split_rows <- split(out, paste(out$source_provider, out$provider_dataset_id, sep = "::"), drop = TRUE)
  deduped <- lapply(split_rows, function(chunk) {
    idx <- order(-ifelse(is.na(chunk$candidate_score), -Inf, chunk$candidate_score))[[1]]
    chunk[idx, , drop = FALSE]
  })
  do.call(rbind, deduped)
}

provider_build_file_candidates <- function(df, provider_name, dataset_table, candidate_score_default = 0.5, candidate_keep_default = TRUE) {
  if (!nrow(df)) {
    return(provider_file_schema(0))
  }

  dataset_id <- provider_extract_column(df, c(
    "provider_dataset_id", "dataset_id", "datasetid", "study_id", "studyid", "id", "doi", "dryad_dataset_doi"
  ))
  dataset_id <- provider_trim_to_na(dataset_id)
  missing_id <- is.na(dataset_id)
  if (any(missing_id)) {
    dataset_id[missing_id] <- sprintf("%s_dataset_%s", provider_name, seq_len(sum(missing_id)))
  }

  file_path <- provider_trim_to_na(provider_extract_column(df, c(
    "file_path", "path", "filename", "file_name", "file", "download_file"
  )))
  file_url <- provider_trim_to_na(provider_extract_column(df, c(
    "download_href", "url", "download_url", "file_url", "href", "link"
  )))

  out <- data.frame(
    source_provider = rep(provider_name, nrow(df)),
    provider_dataset_id = dataset_id,
    provider_file_id = provider_trim_to_na(provider_extract_column(df, c("provider_file_id", "file_id", "id_file"))),
    file_path = file_path,
    file_size = provider_to_numeric(provider_extract_column(df, c("file_size", "size", "size_bytes", "bytes"))),
    mime_type = provider_trim_to_na(provider_extract_column(df, c("mime_type", "mime", "content_type", "file_type"))),
    file_status = provider_trim_to_na(provider_extract_column(df, c("file_status", "status"))),
    download_href = file_url,
    candidate_score = provider_to_numeric(
      provider_extract_column(df, c("candidate_score", "score", "relevance_score")),
      default = candidate_score_default
    ),
    candidate_keep = provider_to_logical(
      provider_extract_column(df, c("candidate_keep", "keep", "include")),
      default = candidate_keep_default
    ),
    query_term = provider_trim_to_na(provider_extract_column(df, c("query_term", "search_term", "query", "keyword"))),
    source_title = provider_trim_to_na(provider_extract_column(df, c("source_title", "title", "dataset_title", "study_title"))),
    source_authors = provider_trim_to_na(provider_extract_column(df, c("source_authors", "authors", "creator", "creators", "author_list"))),
    source_subjects = provider_trim_to_na(provider_extract_column(df, c("source_subjects", "subjects", "subject", "keywords", "tags"))),
    source_abstract = provider_trim_to_na(provider_extract_column(df, c("source_abstract", "abstract", "description", "summary"))),
    stringsAsFactors = FALSE
  )

  supports <- provider_infer_file_support(out$file_path)
  out$file_supported_tabular <- supports$file_supported_tabular
  out$file_supported_container <- supports$file_supported_container

  out <- provider_complete_file_schema(out)

  if (nrow(dataset_table)) {
    key <- paste(dataset_table$source_provider, dataset_table$provider_dataset_id, sep = "::")
    score_map <- dataset_table$candidate_score
    keep_map <- dataset_table$candidate_keep
    names(score_map) <- key
    names(keep_map) <- key

    out_key <- paste(out$source_provider, out$provider_dataset_id, sep = "::")
    missing_score <- is.na(out$candidate_score)
    if (any(missing_score)) {
      mapped <- score_map[out_key[missing_score]]
      out$candidate_score[missing_score] <- ifelse(is.na(mapped), candidate_score_default, mapped)
    }
    missing_keep <- is.na(out$candidate_keep)
    if (any(missing_keep)) {
      mapped <- keep_map[out_key[missing_keep]]
      out$candidate_keep[missing_keep] <- ifelse(is.na(mapped), candidate_keep_default, mapped)
    }
  }

  out
}

provider_ingest_manifest <- function(provider_name, manifest_path, output_dir,
                                     candidate_score_default = 0.5,
                                     candidate_keep_default = TRUE) {
  manifest <- provider_read_manifest(manifest_path)

  dataset_table <- provider_build_dataset_candidates(
    manifest,
    provider_name = provider_name,
    candidate_score_default = candidate_score_default,
    candidate_keep_default = candidate_keep_default
  )

  file_table <- provider_build_file_candidates(
    manifest,
    provider_name = provider_name,
    dataset_table = dataset_table,
    candidate_score_default = candidate_score_default,
    candidate_keep_default = candidate_keep_default
  )

  provider_output_dir <- file.path(output_dir, "providers", provider_name)
  dir.create(provider_output_dir, recursive = TRUE, showWarnings = FALSE)

  dataset_path <- file.path(provider_output_dir, "candidate_datasets.csv")
  file_path <- file.path(provider_output_dir, "candidate_files.csv")

  utils::write.csv(dataset_table, dataset_path, row.names = FALSE, na = "")
  utils::write.csv(file_table, file_path, row.names = FALSE, na = "")

  list(
    provider = provider_name,
    dataset_path = dataset_path,
    file_path = file_path,
    dataset_rows = nrow(dataset_table),
    file_rows = nrow(file_table)
  )
}
