`%||%` <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

dryad_is_supported_tabular_path <- function(path) {
  lower_path <- tolower(path)
  any(endsWith(lower_path, c(".csv", ".tsv", ".txt", ".tab", ".xlsx", ".xls")))
}

dryad_is_supported_archive_path <- function(path) {
  lower_path <- tolower(path)
  any(endsWith(lower_path, c(".zip", ".tar", ".tar.gz", ".tgz", ".gz")))
}

dryad_make_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

dryad_copy_gz_to_file <- function(path, out_dir) {
  dryad_make_dir(out_dir)
  out_file <- file.path(out_dir, sub("\\.gz$", "", basename(path), ignore.case = TRUE))
  input_con <- gzfile(path, open = "rb")
  on.exit(close(input_con), add = TRUE)
  output_con <- file(out_file, open = "wb")
  on.exit(close(output_con), add = TRUE)
  repeat {
    bytes <- readBin(input_con, what = raw(), n = 65536)
    if (!length(bytes)) {
      break
    }
    writeBin(bytes, output_con)
  }
  out_file
}

dryad_extract_supported_files <- function(path, work_dir = tempfile("dryad_extract_")) {
  dryad_make_dir(work_dir)

  if (dryad_is_supported_tabular_path(path)) {
    return(list(paths = path, extracted = FALSE, message = "direct_tabular_file"))
  }

  if (!dryad_is_supported_archive_path(path)) {
    return(list(paths = character(0), extracted = FALSE, message = "unsupported_file_type"))
  }

  lower_path <- tolower(path)
  extracted_paths <- character(0)

  if (endsWith(lower_path, ".zip")) {
    utils::unzip(path, exdir = work_dir)
    extracted_paths <- list.files(work_dir, recursive = TRUE, full.names = TRUE)
  } else if (endsWith(lower_path, ".tar") || endsWith(lower_path, ".tar.gz") || endsWith(lower_path, ".tgz")) {
    utils::untar(path, exdir = work_dir)
    extracted_paths <- list.files(work_dir, recursive = TRUE, full.names = TRUE)
  } else if (endsWith(lower_path, ".gz")) {
    extracted_paths <- dryad_copy_gz_to_file(path, work_dir)
  }

  tabular_paths <- extracted_paths[file.exists(extracted_paths) & !dir.exists(extracted_paths) & vapply(extracted_paths, dryad_is_supported_tabular_path, logical(1))]
  list(paths = tabular_paths, extracted = TRUE, message = "archive_extracted")
}

dryad_safe_readlines <- function(path, n = 1L) {
  # Try UTF-8 first, fall back to latin1 for files with non-UTF-8 bytes
  tryCatch(
    readLines(path, n = n, warn = FALSE, encoding = "UTF-8"),
    error = function(e) {
      tryCatch(
        readLines(path, n = n, warn = FALSE, encoding = "latin1"),
        error = function(e2) character(0)
      )
    }
  )
}

dryad_detect_delimiter <- function(path) {
  lower_path <- tolower(path)
  if (endsWith(lower_path, ".tsv") || endsWith(lower_path, ".tab")) {
    return("\t")
  }

  first_line <- dryad_safe_readlines(path, n = 1L)
  if (!length(first_line) || !nzchar(first_line[[1]])) {
    return(",")
  }
  first_line <- first_line[[1]]

  comma_count <- lengths(regmatches(first_line, gregexpr(",", first_line, fixed = TRUE)))
  tab_count <- lengths(regmatches(first_line, gregexpr("\t", first_line, fixed = TRUE)))
  semi_count <- lengths(regmatches(first_line, gregexpr(";", first_line, fixed = TRUE)))

  if (tab_count >= comma_count && tab_count >= semi_count) return("\t")
  if (semi_count > comma_count) return(";")
  ","
}

dryad_is_excel_path <- function(path) {
  lower_path <- tolower(path)
  endsWith(lower_path, ".xlsx") || endsWith(lower_path, ".xls")
}

dryad_sheet_marker_path <- function(path, sheet_name) {
  paste0(path, "#sheet=", sheet_name)
}

dryad_read_excel_workbook <- function(path) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("Package 'readxl' is required to read Excel files. Install with: install.packages('readxl')",
         call. = FALSE)
  }

  sheets <- readxl::excel_sheets(path)
  if (!length(sheets)) {
    return(list(tables = list(), log = list(list(
      extracted_path = path,
      status = "skipped",
      message = paste0("No sheets found in Excel file: ", path)
    ))))
  }

  tables <- list()
  log_rows <- list()

  for (sheet_name in sheets) {
    sheet_path <- dryad_sheet_marker_path(path, sheet_name)
    sheet_result <- tryCatch(
      as.data.frame(
        readxl::read_excel(path, sheet = sheet_name, .name_repair = "unique"),
        stringsAsFactors = FALSE,
        check.names = FALSE
      ),
      error = function(e) e
    )

    if (inherits(sheet_result, "error")) {
      log_rows[[length(log_rows) + 1L]] <- list(
        extracted_path = sheet_path,
        status = "skipped",
        message = conditionMessage(sheet_result)
      )
      next
    }

    tables[[length(tables) + 1L]] <- list(
      path = path,
      sheet_name = sheet_name,
      display_path = sheet_path,
      data = sheet_result
    )
    log_rows[[length(log_rows) + 1L]] <- list(
      extracted_path = sheet_path,
      status = "read",
      message = sprintf("Loaded %s rows x %s columns", nrow(sheet_result), ncol(sheet_result))
    )
  }

  list(tables = tables, log = log_rows)
}

dryad_read_tabular_file <- function(path) {
  lower_path <- tolower(path)

  # Excel files: use readxl if available
  if (dryad_is_excel_path(path)) {
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop("Package 'readxl' is required to read Excel files. Install with: install.packages('readxl')",
           call. = FALSE)
    }
    sheets <- readxl::excel_sheets(path)
    if (length(sheets) == 0L) stop("No sheets found in Excel file: ", path, call. = FALSE)
    # Return first sheet; caller loops over tables so additional sheets are not seen
    return(as.data.frame(
      readxl::read_excel(path, sheet = 1L, .name_repair = "unique"),
      stringsAsFactors = FALSE, check.names = FALSE
    ))
  }

  delim <- dryad_detect_delimiter(path)

  # Detect encoding: try UTF-8 first, fall back to latin1
  enc <- tryCatch({
    con <- file(path, open = "r", encoding = "UTF-8")
    on.exit(close(con))
    readLines(con, n = 5L, warn = FALSE)
    "UTF-8"
  }, error = function(e) "latin1")

  utils::read.table(
    path,
    header = TRUE,
    sep = delim,
    quote = '"',
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE,
    fileEncoding = enc
  )
}

dryad_read_supported_inputs <- function(path) {
  extracted <- dryad_extract_supported_files(path)
  log_rows <- list()
  tables <- list()

  if (!length(extracted$paths)) {
    log_rows[[1]] <- data.frame(
      source_path = path,
      extracted_path = NA_character_,
      status = "skipped",
      message = extracted$message,
      stringsAsFactors = FALSE
    )
    return(list(tables = tables, log = do.call(rbind, log_rows)))
  }

  for (table_path in extracted$paths) {
    if (dryad_is_excel_path(table_path)) {
      workbook_result <- tryCatch(
        dryad_read_excel_workbook(table_path),
        error = function(e) e
      )

      if (inherits(workbook_result, "error")) {
        log_rows[[length(log_rows) + 1L]] <- data.frame(
          source_path = path,
          extracted_path = table_path,
          status = "skipped",
          message = conditionMessage(workbook_result),
          stringsAsFactors = FALSE
        )
        next
      }

      if (length(workbook_result$tables)) {
        for (sheet_table in workbook_result$tables) {
          tables[[length(tables) + 1L]] <- sheet_table
        }
      }

      if (length(workbook_result$log)) {
        for (sheet_log in workbook_result$log) {
          log_rows[[length(log_rows) + 1L]] <- data.frame(
            source_path = path,
            extracted_path = sheet_log$extracted_path,
            status = sheet_log$status,
            message = sheet_log$message,
            stringsAsFactors = FALSE
          )
        }
      }

      next
    }

    table_result <- tryCatch(
      dryad_read_tabular_file(table_path),
      error = function(e) e
    )

    if (inherits(table_result, "error")) {
      log_rows[[length(log_rows) + 1L]] <- data.frame(
        source_path = path,
        extracted_path = table_path,
        status = "skipped",
        message = conditionMessage(table_result),
        stringsAsFactors = FALSE
      )
      next
    }

    tables[[length(tables) + 1L]] <- list(path = table_path, data = table_result)
    log_rows[[length(log_rows) + 1L]] <- data.frame(
      source_path = path,
      extracted_path = table_path,
      status = "read",
      message = sprintf("Loaded %s rows x %s columns", nrow(table_result), ncol(table_result)),
      stringsAsFactors = FALSE
    )
  }

  list(
    tables = tables,
    log = do.call(rbind, log_rows)
  )
}
