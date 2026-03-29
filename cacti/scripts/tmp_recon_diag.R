suppressPackageStartupMessages({library(readr); library(dplyr); library(stringr)})

acc <- read_csv('cacti/data_processed/bien_cactaceae_species_accepted.csv', show_col_types = FALSE)
traits <- read_csv('cacti/data_raw/bien_cactaceae_traits_all.csv', show_col_types = FALSE)

cat('FILE cacti_master_traits_long:', file.exists('cacti/data_processed/cacti_master_traits_long.csv'), '\n')
cat('ACC_ROWS', nrow(acc), '\n')
cat('ACC_UNIQUE', n_distinct(acc$scrubbed_species_binomial), '\n')
cat('ACC_EMPTY', sum(is.na(acc$scrubbed_species_binomial) | acc$scrubbed_species_binomial == ''), '\n')
cat('ACC_HYBRID_X', sum(str_detect(acc$scrubbed_species_binomial, '\\bx\\b')), '\n')

cat('TRAITS_ROWS', nrow(traits), '\n')
cat('TRAITS_EMPTY_SPP', sum(is.na(traits$scrubbed_species_binomial) | traits$scrubbed_species_binomial == ''), '\n')
cat(
  'TRAITS_GENUS_ONLY',
  sum(!is.na(traits$scrubbed_taxon_name_no_author) & !is.na(traits$scrubbed_genus) &
        traits$scrubbed_taxon_name_no_author == traits$scrubbed_genus),
  '\n'
)
cat(
  'TRAITS_MORPHO_MARKERS',
  sum(str_detect(coalesce(traits$scrubbed_species_binomial_with_morphospecies, ''), '\\b(sp\\.|spp\\.|cf\\.|aff\\.|nr\\.)\\b')),
  '\n'
)

if ('matched_taxonomic_status' %in% names(traits)) {
  ctab <- traits %>% count(matched_taxonomic_status, sort = TRUE)
  for (i in seq_len(nrow(ctab))) {
    cat('MATCHED_STATUS', ctab$matched_taxonomic_status[i], ctab$n[i], '\n')
  }
}

if ('scrubbed_taxonomic_status' %in% names(traits)) {
  ctab2 <- traits %>% count(scrubbed_taxonomic_status, sort = TRUE)
  for (i in seq_len(nrow(ctab2))) {
    cat('SCRUBBED_STATUS', ctab2$scrubbed_taxonomic_status[i], ctab2$n[i], '\n')
  }
}

syn_to_acc <- traits %>% filter(matched_taxonomic_status == 'Synonym', scrubbed_taxonomic_status == 'Accepted')
cat('SYN_TO_ACC_ROWS', nrow(syn_to_acc), '\n')
cat('SYN_TO_ACC_UNIQ_VERBATIM', n_distinct(syn_to_acc$verbatim_scientific_name), '\n')
cat('SYN_TO_ACC_UNIQ_ACCEPTED', n_distinct(syn_to_acc$scrubbed_species_binomial), '\n')

if ('tnrs_warning' %in% names(traits)) {
  tw <- traits %>% mutate(flag = ifelse(is.na(tnrs_warning) | tnrs_warning == '', '<none>', tnrs_warning)) %>% count(flag, sort = TRUE)
  for (i in seq_len(min(10, nrow(tw)))) {
    cat('TNRS_WARNING', tw$flag[i], tw$n[i], '\n')
  }
}

trait_species <- traits %>%
  filter(!is.na(scrubbed_species_binomial), scrubbed_species_binomial != '') %>%
  pull(scrubbed_species_binomial) %>%
  unique()

not_in_acc <- setdiff(trait_species, unique(acc$scrubbed_species_binomial))
cat('TRAIT_SPECIES_NOT_IN_ACCEPTED', length(not_in_acc), '\n')
if (length(not_in_acc) > 0) {
  ex <- head(sort(not_in_acc), 15)
  for (x in ex) {
    cat('NOT_IN_ACCEPTED_EX', x, '\n')
  }
}

needed <- c('url_source', 'source_citation', 'id', 'access', 'name_matched_author', 'scrubbed_author')
for (nm in needed) {
  miss <- if (nm %in% names(traits)) sum(is.na(traits[[nm]]) | traits[[nm]] == '') else NA_integer_
  cat('FIELD', nm, 'PRESENT', nm %in% names(traits), 'MISSING', miss, '\n')
}

cat(
  'HAS_BACKBONE_VERSION_FIELD',
  any(names(traits) %in% c('backbone_version_or_release', 'taxonomy_version', 'tnrs_version', 'backbone_version')),
  '\n'
)
