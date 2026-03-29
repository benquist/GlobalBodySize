#!/usr/bin/env Rscript
# =============================================================================
# Full Cacti Trait Pipeline
# Sources: BIEN (all traits) + Wikipedia infobox scraping
# Output: master species x trait dataset with per-row provenance
# =============================================================================

suppressPackageStartupMessages({
  pkgs <- c("BIEN","dplyr","stringr","readr","httr2","jsonlite",
            "tibble","tidyr","rvest","xml2","purrr")
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly=TRUE)]
  if (length(miss)) install.packages(miss, repos="https://cloud.r-project.org")
  invisible(lapply(pkgs, library, character.only=TRUE))
})

base_dir  <- "cacti"
raw_dir   <- file.path(base_dir, "data_raw")
proc_dir  <- file.path(base_dir, "data_processed")
dir.create(raw_dir,  recursive=TRUE, showWarnings=FALSE)
dir.create(proc_dir, recursive=TRUE, showWarnings=FALSE)

# ---------------------------------------------------------------------------
# 1.  BIEN taxonomy — full accepted species list
# ---------------------------------------------------------------------------
cat("[1/5] BIEN taxonomy...\n")
bien_tax <- BIEN_taxonomy_family("Cactaceae")
accepted <- bien_tax |>
  filter(scrubbed_taxonomic_status == "Accepted",
         !is.na(scrubbed_species_binomial)) |>
  distinct(scrubbed_species_binomial, scrubbed_genus) |>
  arrange(scrubbed_species_binomial)
write_csv(accepted, file.path(proc_dir,"bien_cactaceae_species_accepted.csv"), na="")
cat("  Accepted species:", nrow(accepted), "\n")

# ---------------------------------------------------------------------------
# 2.  BIEN traits — ALL available traits for Cactaceae
# ---------------------------------------------------------------------------
cat("[2/5] BIEN all traits...\n")
bt_raw <- BIEN_trait_family("Cactaceae", all.taxonomy=TRUE, source.citation=TRUE)
names(bt_raw) <- make.unique(names(bt_raw))
write_csv(bt_raw, file.path(raw_dir,"bien_cactaceae_traits_all.csv"), na="")
cat("  BIEN trait records:", nrow(bt_raw), "\n")

# Normalise to long format with consistent columns
bien_long <- bt_raw |>
  transmute(
    species        = str_squish(scrubbed_species_binomial),
    genus          = scrubbed_genus,
    family         = scrubbed_family,
    trait_name     = trait_name,
    trait_value    = as.character(trait_value),
    unit           = unit,
    method         = method,
    latitude       = as.numeric(latitude),
    longitude      = as.numeric(longitude),
    elevation_m    = as.numeric(elevation_m),
    source_dataset = "BIEN",
    source_url     = coalesce(url_source, "https://bien.nceas.ucsb.edu/bien/"),
    source_record_id = as.character(id),
    project_pi     = project_pi,
    retrieved_utc  = format(Sys.time(), tz="UTC", usetz=TRUE)
  ) |>
  filter(!is.na(species), species != "")

write_csv(bien_long, file.path(proc_dir,"bien_cacti_all_traits_long.csv"), na="")
cat("  Clean BIEN rows:", nrow(bien_long), "\n")

# ---------------------------------------------------------------------------
# 3.  Wikipedia infobox scraper
# ---------------------------------------------------------------------------
cat("[3/5] Wikipedia scraping for", nrow(accepted), "species...\n")

# Helper: fetch Wikipedia REST summary + page extract
# Uses the Action API for infobox data via the WikiText parse endpoint
wp_get_infobox <- function(species_name, retry=2) {
  title <- str_replace_all(species_name, " ", "_")
  url   <- str_glue("https://en.wikipedia.org/api/rest_v1/page/summary/{title}")

  tryCatch({
    resp <- request(url) |>
      req_user_agent("cacti-trait-pipeline/1.0 (research; local)") |>
      req_timeout(20) |>
      req_retry(max_tries=retry) |>
      req_perform()

    if (resp_status(resp) != 200) return(NULL)
    js <- resp_body_json(resp, simplifyVector=TRUE)

    # Also fetch the wikitext for infobox parsing
    parse_url <- "https://en.wikipedia.org/w/api.php"
    parse_resp <- request(parse_url) |>
      req_url_query(
        action  = "parse",
        page    = species_name,
        prop    = "wikitext",
        format  = "json",
        section = 0
      ) |>
      req_user_agent("cacti-trait-pipeline/1.0 (research; local)") |>
      req_timeout(20) |>
      req_retry(max_tries=retry) |>
      req_perform()

    wikitext <- ""
    if (resp_status(parse_resp) == 200) {
      pj <- resp_body_json(parse_resp, simplifyVector=TRUE)
      wikitext <- pj$parse$wikitext[["*"]] %||% ""
    }

    list(
      extract  = js$extract  %||% "",
      wikitext = wikitext,
      wp_url   = js$content_urls$desktop$page %||%
                   str_glue("https://en.wikipedia.org/wiki/{title}")
    )
  }, error=function(e) NULL)
}

# Helper: parse key trait fields from wikitext infobox
parse_wp_traits <- function(species, wt, wp_url) {
  rows <- list()

  add_row <- function(trait, value, unit="", note="") {
    if (!is.na(value) && str_trim(value) != "") {
      rows[[length(rows)+1]] <<- tibble(
        species        = species,
        trait_name     = trait,
        trait_value    = str_trim(value),
        unit           = unit,
        method         = paste0("Wikipedia infobox", if(note!="") paste0("; ", note) else ""),
        source_dataset = "Wikipedia",
        source_url     = wp_url,
        source_record_id = str_replace(wp_url, ".*wiki/", ""),
        retrieved_utc  = format(Sys.time(), tz="UTC", usetz=TRUE)
      )
    }
  }

  # Regex helpers for infobox fields
  get_field <- function(pattern) {
    m <- str_match(wt, regex(pattern, ignore_case=TRUE))
    if (!is.na(m[1,1])) m[1,2] else NA_character_
  }

  # Flower color
  fc <- get_field("\\|\\s*flower_color[^=]*=([^\n|\\}]+)")
  if (is.na(fc)) fc <- get_field("flower.{0,5}col(?:ou)?r[^=]*=([^\n|\\}]+)")
  if (!is.na(fc)) {
    fc_clean <- str_remove_all(fc, "\\{\\{[^}]*\\}\\}|\\[\\[[^\\]]*\\]\\]|<!--.*?-->")
    fc_clean <- str_squish(fc_clean)
    add_row("flower color", fc_clean, note="Wikipedia infobox field: flower_color")
  }

  # Height
  ht <- get_field("\\|\\s*(?:height|max_height)[^=]*=\\s*([0-9][^\n|\\}]*)")
  if (!is.na(ht)) {
    unit_str <- if (str_detect(ht, "[cm]m")) str_extract(ht, "[cm]m") else "see value"
    ht_val   <- str_extract(ht, "[0-9.,–\\-]+")
    add_row("maximum whole plant height", ht_val, unit=unit_str, note="Wikipedia infobox")
  }

  # Trunk/stem diameter
  diam <- get_field("\\|\\s*(?:trunk_diameter|stem_diameter|diameter)[^=]*=\\s*([0-9][^\n|\\}]*)")
  if (!is.na(diam)) {
    unit_str <- if (str_detect(diam, "[cm]m")) str_extract(diam, "[cm]m") else "see value"
    d_val    <- str_extract(diam, "[0-9.,–\\-]+")
    add_row("stem diameter", d_val, unit=unit_str, note="Wikipedia infobox")
  }

  # Growth form
  gf <- get_field("\\|\\s*growth_form[^=]*=([^\n|\\}]+)")
  if (is.na(gf)) gf <- get_field("\\|\\s*habit[^=]*=([^\n|\\}]+)")
  if (!is.na(gf)) {
    gf_clean <- str_remove_all(gf, "\\{\\{[^}]*\\}\\}|\\[\\[[^\\]]*\\]\\]")
    add_row("whole plant growth form", str_squish(gf_clean), note="Wikipedia infobox")
  }

  # Native range / distribution (free-text)
  nr <- get_field("\\|\\s*native_range[^=]*=([^\n|\\}]+)")
  if (is.na(nr)) nr <- get_field("\\|\\s*range[^=]*=([^\n|\\}]+)")
  if (!is.na(nr)) {
    nr_clean <- str_remove_all(nr, "\\{\\{[^}]*\\}\\}|\\[\\[[^\\]]*\\]\\]")
    add_row("native range", str_squish(nr_clean), note="Wikipedia infobox")
  }

  if (length(rows) == 0) return(NULL)
  bind_rows(rows)
}

# Extract height/diameter/flower color from free text if infobox empty
parse_wp_text_fallback <- function(species, extract, wp_url) {
  rows <- list()
  add <- function(trait, value, unit="") {
    rows[[length(rows)+1]] <<- tibble(
      species=species, trait_name=trait, trait_value=str_trim(value),
      unit=unit, method="Wikipedia article text (regex)",
      source_dataset="Wikipedia", source_url=wp_url,
      source_record_id=str_replace(wp_url, ".*wiki/", ""),
      retrieved_utc=format(Sys.time(), tz="UTC", usetz=TRUE)
    )
  }

  # Height patterns: "grows to X m", "up to X cm tall", "X–Y m tall"
  hm <- str_match(extract,
    regex("(?:reaches?|grows? to|up to|height of|tall(?:er)? than)\\s*([0-9.,]+)\\s*(m|cm|ft)(?:\\s*(?:to|–|-)\\s*([0-9.,]+)\\s*(m|cm|ft))?",
          ignore_case=TRUE))
  if (!is.na(hm[1,1])) {
    val  <- if (!is.na(hm[1,4])) paste0(hm[1,2], "–", hm[1,4]) else hm[1,2]
    unit <- coalesce(hm[1,5], hm[1,3], "m")
    add("maximum whole plant height", val, unit)
  }

  # Flower color patterns: "flowers are X", "yellow flowers", "pink-flowered"
  fc <- str_match(extract,
    regex("(white|yellow|red|pink|orange|purple|magenta|cream|greenish|rose|violet)(?:\\s+and\\s+(white|yellow|red|pink|orange|purple|magenta))?\\s+flower",
          ignore_case=TRUE))
  if (!is.na(fc[1,1])) {
    color_val <- if (!is.na(fc[1,3])) paste(fc[1,2], "and", fc[1,3]) else fc[1,2]
    add("flower color", tolower(color_val))
  }
  fc2 <- str_match(extract,
    regex("flower(?:s)?\\s+(?:are|is|with)\\s+([a-z ,]+?)(?:\\.|,|;|\\band\\b)",
          ignore_case=TRUE))
  if (!is.na(fc2[1,1]) && nchar(fc2[1,2]) < 60) {
    add("flower color", tolower(str_squish(fc2[1,2])), note="text extraction")
  }

  if (length(rows)==0) return(NULL)
  bind_rows(rows)
}

# Run scraper over all accepted species with polite pacing
wp_results <- vector("list", nrow(accepted))
n_species  <- nrow(accepted)
interval   <- 0.4  # seconds between requests (polite)

for (i in seq_len(n_species)) {
  sp <- accepted$scrubbed_species_binomial[i]

  if (i %% 100 == 0 || i == 1) {
    cat(sprintf("  Wikipedia: %d / %d (%.0f%%) — %s\n",
                i, n_species, 100*i/n_species, sp))
  }

  wp <- wp_get_infobox(sp)
  if (!is.null(wp)) {
    from_infobox <- parse_wp_traits(sp, wp$wikitext, wp$wp_url)
    from_text    <- if(!is.null(from_infobox) && nrow(from_infobox) > 0) NULL
                    else parse_wp_text_fallback(sp, wp$extract, wp$wp_url)
    wp_results[[i]] <- bind_rows(from_infobox, from_text)
  }

  Sys.sleep(interval)
}

wp_long <- bind_rows(wp_results) |>
  filter(!is.na(trait_value), str_trim(trait_value) != "")

write_csv(wp_long, file.path(raw_dir,"wikipedia_cacti_traits_raw.csv"), na="")
cat("  Wikipedia trait records extracted:", nrow(wp_long), "\n")
cat("  Species with Wikipedia data:", length(unique(wp_long$species)), "\n")

# ---------------------------------------------------------------------------
# 4.  Combine BIEN + Wikipedia into master long-format dataset
# ---------------------------------------------------------------------------
cat("[4/5] Building master dataset...\n")

# Harmonise columns
harmonise <- function(df) {
  expected <- c("species","genus","family","trait_name","trait_value","unit",
                "method","latitude","longitude","elevation_m",
                "source_dataset","source_url","source_record_id",
                "project_pi","retrieved_utc")
  for (col in expected) {
    if (!col %in% names(df)) df[[col]] <- NA_character_
  }
  df[, expected]
}

master_long <- bind_rows(
  harmonise(bien_long),
  harmonise(wp_long)
) |>
  mutate(
    species   = str_squish(as.character(species)),
    trait_name = str_squish(as.character(trait_name)),
    trait_value = str_squish(as.character(trait_value))
  ) |>
  filter(!is.na(species), species != "",
         !is.na(trait_name), trait_name != "",
         !is.na(trait_value), trait_value != "")

write_csv(master_long, file.path(proc_dir,"cacti_master_traits_long.csv"), na="")
cat("  Master long rows:", nrow(master_long), "\n")

# Wide pivot: one row per species, columns = trait
# For multi-valued traits, collapse to semicolon-delimited
master_wide <- master_long |>
  group_by(species, trait_name) |>
  summarise(
    trait_values   = paste(unique(trait_value), collapse=" | "),
    units          = paste(unique(na.omit(unit)), collapse="; "),
    sources        = paste(unique(source_dataset), collapse="; "),
    source_urls    = paste(unique(source_url), collapse=" | "),
    n_records      = n(),
    .groups = "drop"
  ) |>
  tidyr::pivot_wider(
    names_from   = trait_name,
    values_from  = c(trait_values, units, sources, source_urls, n_records),
    names_glue   = "{trait_name}__{.value}"
  )

write_csv(master_wide, file.path(proc_dir,"cacti_master_traits_wide.csv"), na="")

# Coverage table for the Rmd
coverage_tbl <- master_long |>
  group_by(trait_name, source_dataset) |>
  summarise(
    n_records        = n(),
    n_species        = n_distinct(species),
    example_values   = paste(head(unique(trait_value), 4), collapse=" | "),
    .groups = "drop"
  ) |>
  arrange(trait_name, source_dataset)

write_csv(coverage_tbl, file.path(proc_dir,"cacti_trait_coverage_table.csv"), na="")

# Provenance log
prov_log <- tibble(
  source_dataset       = c("BIEN", "Wikipedia"),
  full_name            = c(
    "Botanical Information and Ecology Network",
    "Wikipedia (English) — per-species article scrape"
  ),
  access_method        = c(
    "R package BIEN::BIEN_trait_family('Cactaceae')",
    "MediaWiki REST v1 /page/summary + Action API wikitext parse"
  ),
  endpoint             = c(
    "https://bien.nceas.ucsb.edu/bien/",
    "https://en.wikipedia.org/api/rest_v1/ and https://en.wikipedia.org/w/api.php"
  ),
  traits_extracted     = c(
    paste(sort(unique(bien_long$trait_name)), collapse="; "),
    "flower color, maximum whole plant height, stem diameter, whole plant growth form, native range"
  ),
  license_or_terms     = c(
    "BIEN data are publicly available; cite BIEN and original data providers",
    "CC BY-SA 4.0 — cite Wikipedia per-article URL"
  ),
  query_timestamp_utc  = format(Sys.time(), tz="UTC", usetz=TRUE)
)

write_csv(prov_log, file.path(proc_dir,"cacti_provenance_log.csv"), na="")

cat("[5/5] Summary\n")
cat("  Total long-format records:", nrow(master_long), "\n")
cat("  Unique species with any trait:", length(unique(master_long$species)), "\n")
cat("  Unique traits:", length(unique(master_long$trait_name)), "\n")
cat("  Output dir:", normalizePath(proc_dir), "\n")
cat("Done.\n")
