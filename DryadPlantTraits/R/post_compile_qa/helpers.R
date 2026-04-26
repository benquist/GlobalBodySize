`%||%` <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

pcqa_parse_named_args <- function(args) {
  values <- list()
  if (!length(args)) return(values)

  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }

  values
}

pcqa_find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") return(dirname(cwd))
  candidate <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(candidate)) return(candidate)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

pcqa_source_modules <- function(root = pcqa_find_project_root()) {
  files <- c(
    file.path(root, "R", "post_compile_qa", "helpers.R"),
    file.path(root, "R", "post_compile_qa", "species_gate.R"),
    file.path(root, "R", "post_compile_qa", "range_scoring.R"),
    file.path(root, "R", "post_compile_qa", "triage.R")
  )
  invisible(lapply(files, source, local = FALSE))
}

pcqa_make_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

pcqa_is_blank <- function(x) {
  x_chr <- trimws(as.character(x))
  is.na(x) | !nzchar(x_chr)
}

pcqa_binomial_ok <- function(x) {
  x_chr <- trimws(as.character(x))
  grepl("^[A-Z][A-Za-z.-]+\\s+[a-z][A-Za-z.-]+$", x_chr)
}

pcqa_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

pcqa_write_csv <- function(df, path) {
  utils::write.csv(df, path, row.names = FALSE, na = "")
}
