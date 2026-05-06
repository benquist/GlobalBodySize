# download_15_glopnet_leaf.R
# Dataset 15: GLOPNET leaf traits — Wright et al. 2004 Nature
# Paper DOI: https://doi.org/10.1038/nature02403
# Status: PARTIAL — supplementary data download from Nature; may require institutional access.
# Alternative: GLOPNET traits also available in TRY database (preferred route).

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D15"
DATASET_NAME <- "GLOPNET leaf traits — Wright et al. 2004 Nature"
PAPER_DOI    <- "https://doi.org/10.1038/nature02403"
DEST_DIR     <- here::here("data", "raw", "15_glopnet_leaf")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# GLOPNET Leaf Traits — Wright et al. 2004 Nature

Citation: Wright IJ et al. (2004) The worldwide leaf economics spectrum.
          Nature 428:821–827. https://doi.org/10.1038/nature02403

## Status: PARTIAL — supplementary data access may require institutional subscription

The GLOPNET dataset was published as supplementary data with the paper.

## Option A: Nature supplementary file (may require subscription)
1. Navigate to: https://www.nature.com/articles/nature02403#Sec15
2. Look for 'Supplementary information' links.
3. Download the Excel/CSV supplementary file.
4. Save to: data/raw/15_glopnet_leaf/
5. Record: filename, access date, institutional access required (yes/no).

## Option B: TRY database (RECOMMENDED — more complete, programmatic access)
GLOPNET traits are incorporated into the TRY database. Relevant TRY trait IDs:
  - TraitID 11: Leaf area per leaf dry mass (SLA, m2/kg)
  - TraitID 13: Leaf nitrogen content per leaf dry mass (mg/g)
  - TraitID 15: Leaf phosphorus content per leaf dry mass (mg/g)
  - TraitID 3115: Leaf dark respiration rate per leaf dry mass
Access via: https://www.try-db.org (requires free registration; see D16 instructions)

## Key trait variables in GLOPNET
- LL: leaf lifespan (months)
- LMA: leaf mass per area (g/m²)
- Nmass: N per unit mass (mg/g)
- Narea: N per unit area (g/m²)
- Pmass: P per unit mass (mg/g)
- Amass: photosynthetic capacity per unit mass (nmol/g/s)
- Aarea: photosynthetic capacity per unit area (μmol/m²/s)
- Rd mass: dark respiration per unit mass (nmol/g/s)

## Unit note
Verify unit column headers against Table S1 in the paper. Units differ between
mass-based and area-based expressions.
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_glopnet_leaf.txt"))

message("D15 GLOPNET: PARTIAL. Manual Nature supp download or TRY request required.")
log_download(DATASET_ID, DATASET_NAME, PAPER_DOI,
             file.path(DEST_DIR, "README_glopnet_leaf.txt"),
             "PARTIAL", NA, NA, "manual — Nature supplementary or TRY database",
             "Supp file URL unstable; recommend TRY database route for reproducibility.")
