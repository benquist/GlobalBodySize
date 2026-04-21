# BIEN Historical Data Ingestion App: Comprehensive Redesign Proposal

**Date:** April 2025  
**Prepared by:** Supervisor Agent Coordinating Biodiversity Science, Engineering, and Taxonomy Specialists  
**Status:** Design Phase - Ready for Review

---

## EXECUTIVE SUMMARY

The current BIEN Shiny app is a **data browser** for exploratory queries. The actual ecologist need is a **data preparation pipeline** for multi-file historical observation data destined for BIEN submission.

This redesign transforms the app from "browse BIEN records" to "prepare your data for BIEN submission" by adding:
- Multi-file upload and linking interface
- Darwin Core schema mapping  
- Automated data quality validation
- Species name reconciliation
- Guided step-by-step workflow

**Key Innovation:** Instead of requiring ecologists to understand Darwin Core before uploading, the app takes their messy, multi-file data and *progressively* transforms it while checking quality at each step.

---

## PART 1: PROBLEM ANALYSIS

### Current App Limitations

| Aspect | Current | Problem |
|--------|---------|---------|
| **Purpose** | BIEN data browser for queries | Doesn't support data *submission* |
| **Input** | Single species name | Can't handle multi-file, messy historical data |
| **Users** | Ecologists exploring data | Doesn't match data *submission* workflow |
| **Output** | Maps, tables of existing BIEN records | Not suitable for preparing new submissions |
| **UX Model** | "Query → Preview → Explore" | Doesn't guide data transformation |

### Real Ecologist Workflow We Need to Support

1. **Data Discovery** → Ecologist reads historical publications, identifies species observations
2. **Data Extraction** → Copy tables from PDFs into Excel/CSV (messy, often multiple files)
3. **Data Organization** → Realize plots are in one table, locations in another, observations scattered
4. **Data Linking** → Match plot IDs to location IDs to observations (error-prone)
5. **Schema Mapping** → Figure out which columns map to Darwin Core fields (overwhelming)
6. **Name Resolution** → Check if "Abies bracteata" is the accepted name (unclear process)
7. **Quality Check** → Find coordinate errors, missing values, duplicates (manual & slow)
8. **Submission** → Export Darwin Core format and submit to BIEN (no current support)

**Ecologist Pain Points:**
- No guidance on Darwin Core standard
- Can't easily join multi-file tables
- Species name checking is opaque (if they do it at all)
- Quality issues found too late (after submission rejected)
- No audit trail for data decisions

---

## PART 2: DESIGN PRINCIPLES

The redesigned app follows these principles:

1. **Guided Workflow** — Users move through 6 logical steps; each step outputs data for the next
2. **Progressive Reveal** — Don't overwhelm with Darwin Core; teach as they map
3. **Fail Fast** — Find quality issues earlier, not after submission
4. **Provenance Preserved** — Every transformation recorded and reviewable
5. **Ecologist Mental Model** — Use terms they know (plot, site, observation) not just Darwin Core jargon
6. **Audit-Ready** — Output suitable for biodiversity data repositories and scientific review

---

## PART 3: NEW APP WORKFLOW (Step-by-Step User Journey)

### **STEP 1: UPLOAD FILES** (10-15 minutes)

**Goal:** Get all raw data into the app; understand structure

**What Ecologist Does:**
- Drags one or more CSV/Excel files into upload area
- App detects format and reads file
- Shows preview: columns, data types, row counts

**What App Does:**
1. Accept multiple files (CSV, XLSX, XLS)
2. Parse each file with `readxl` or `fread()`
3. Display table summary:
   - Filename, format, dimensions
   - Column names and types
   - First 100 rows as preview

**Ecologist Sees:**
- Visual confirmation files loaded correctly
- Early error detection (e.g., "lots of NAs in column X")

**Example Output:**
```
File: plot_metadata.csv
  Format: CSV
  Rows: 15
  Columns: plotID | date | plotSize_m2 | samplingEffort | recordedBy | eventRemarks

File: species_observations.csv
  Format: CSV
  Rows: 127
  Columns: occurrenceID | plotID | scientificName | individualCount
```

---

### **STEP 2: LINK FILES** (5-10 minutes)

**Goal:** Tell the app how to join related tables

**What Ecologist Does:**
- Selects which table is "primary" (usually observations)
- Reviews app's suggestions for matching columns
- Confirms or modifies join strategy

**What App Does:**
1. Analyze column names across all uploaded files
2. Detect ID columns (plotID, siteID, etc.)
3. Find common column names across files
4. Suggest foreign key joins:
   ```
   observations.plotID = plot_metadata.plotID
   plot_metadata.siteID = locations.siteID
   ```
5. Preview the flattened result

**Ecologist Sees:**
- "I found plotID in both files — is that how they're linked?"
- Preview of joined table
- Diagnostics: "127 observations matched to 15 plots" (validation that join worked)

**Example Suggestion:**
```
Primary table: species_observations.csv

Suggested joins:
✓ observations.plotID = plot_metadata.plotID  [Match found in both files]
✓ plot_metadata.siteID = locations.siteID  [Match found in both files]

Result: 127 rows with all metadata flattened
```

---

### **STEP 3: SCHEMA MAPPING** (5 minutes)

**Goal:** Map raw column names to Darwin Core fields

**What Ecologist Does:**
- For each Darwin Core required field, select which column from their data maps to it
- Optionally map optional fields

**What App Does:**
1. Display all Darwin Core required fields with descriptions
2. Let ecologist pick from available columns
3. Build mapping dictionary
4. Show validation: "✓ All required fields mapped"

**Ecologist Sees:**
- Simple dropdown: "scientificName: [scientific_name_]" (pre-filled based on name similarity)
- Explanation of what each field means
- Warning if required field not mapped: "❌ occurrenceID not mapped"

**Example:**
```
Darwin Core Required Fields
────────────────────────────
occurrenceID (unique ID for record):
  [Select] → occurrenceID ✓

scientificName (organism name):
  [Select] → spp_name ✓

eventDate (observation date, YYYY-MM-DD):
  [Select] → date ✓

decimalLatitude (latitude, -90 to 90):
  [Select] → lat ✓

decimalLongitude (longitude, -180 to 180):
  [Select] → lon ✓

basisOfRecord (type: PreservedSpecimen, Observation, Literature, etc.):
  [Select] → (Not mapped) — SELECT ONE

Optional Fields
────────────────
coordinateUncertaintyInMeters
  [Select] → (Not mapped)

samplingEffort
  [Select] → effort_hours
```

---

### **STEP 4: TAXONOMIC RESOLUTION** (10-20 minutes)

**Goal:** Check species names against taxonomic backbone; flag ambiguities

**What Ecologist Does:**
- Clicks "Check Species Names"
- Sees list of any unmatched names
- Resolves ambiguities (if fuzzy matches offered)

**What App Does:**
1. Extract unique scientificName values from mapped column
2. Query GBIF Backbone API for each name (with caching)
3. Classify reconciliation results:
   - ✓ **Exact match** → Accepted name found, no action needed
   - ⚠ **Fuzzy match** → Similar names found, requires user confirmation
   - ✗ **Unresolved** → No matches found, user must decide
4. Build reconciliation table

**Ecologist Sees:**
```
Taxonomic Reconciliation Results
─────────────────────────────────
✓ Exact Matches: 18/20 names
⚠ Fuzzy Matches: 1 name (requires review)
✗ Unresolved: 1 name (not found in GBIF)

Requires Review:
────────────────
Your name: "Abies bracteata"
GBIF matches:
  • "Abies bracteata" (accepted, GBIF ID: 2684245)

Unresolved:
────────────
"Pinus ponderosa subsp. potentior" — not found in GBIF Backbone v2024-11
(Suggestion: Check POWO or provide accepted name manually)
```

**Reconciliation Table Output:**
```
input_name | matched_name | status | backbone | confidence
Abies sp.  | (unresolved) | ambiguous | GBIF 2024-11 | 0
Pinus pon. | Pinus ponderosa | exact | GBIF 2024-11 | 1.0
```

---

### **STEP 5: DATA VALIDATION REPORT** (5 minutes)

**Goal:** Find all quality issues before submission

**What Ecologist Does:**
- Clicks "Run Validation"
- Reviews issues organized by severity
- Decides to proceed or go back to fix issues

**What App Does:**
1. Run tiered validation checks:
   - **Tier 1: BLOCKING** — Will prevent submission
   - **Tier 2: WARNING** — Should review
   - **Tier 3: INFO** — Just informational

2. Check each issue:
   - Required fields present?
   - Coordinates valid (lat: -90 to 90, lon: -180 to 180)?
   - Dates valid ISO 8601?
   - No duplicate occurrenceIDs?
   - Coordinate uncertainty reasonable?
   - Taxonomic names resolved?
   - Abundance data with effort defined?

3. Generate spatial map showing coordinate distribution

**Ecologist Sees:**
```
Data Quality Report
═══════════════════

✓ No Blocking Errors — Data ready to proceed

⚠ Warnings (3 issues):
  • Coordinate uncertainty > 5000m (1 record)
    Location too coarse; consider adding more specific site data
  • Missing samplingEffort (5 records)
    You have abundance counts, but no effort defined
    This makes interpretation ambiguous
  • Potential duplicate (1 record)
    2 records at identical lat/lon on identical date
    Are these the same observation recorded twice?

ℹ Information (2 items):
  • Records from multiple decades
    Oldest: 1987, Newest: 2010
  • Geographic span: 300 km
    Observations spread across coastal range

Map: 127 occurrences plotted
```

---

### **STEP 6: REVIEW & EXPORT** (5 minutes)

**Goal:** Final review; prepare for submission

**What Ecologist Does:**
- Reviews summary statistics
- Completes metadata form (dataset name, citation, license)
- Downloads Darwin Core TSV and metadata YAML
- Submits to BIEN portal (outside this app)

**What App Does:**
1. Show final summary:
   - Row count, geographic extent, date range
   - Metadata completeness
2. Provide editable metadata fields:
   - Dataset name
   - Citation (original publication)
   - Data license (CC0, CC-BY, CC-BY-SA, etc.)
   - Transformation notes
3. Generate Darwin Core TSV with all mapped fields
4. Generate metadata YAML with provenance

**Ecologist Downloads:**
- **darwin_core_export.tsv** — Ready for BIEN submission
- **metadata.yaml** — Provenance and methodology documentation

**Example Darwin Core Output:**
```
occurrenceID  scientificName         eventDate    decimalLatitude decimalLongitude ...
OCC_P001_001  Abies bracteata        2010-05-15   36.582          -121.939
OCC_P001_002  Pinus ponderosa        2010-05-15   36.583          -121.940
...
```

**Example Metadata Output:**
```yaml
dataset_name: "Historical vegetation data from Smith et al. (2010)"
dataset_citation: "Smith, J., et al. (2010). Coastal surveys. J. Ecology 98(3):445-60. DOI: 10.1111/j.xxxx"
data_license: "CC-BY-4.0"
access_date: "2025-04-15"
taxonomic_backbone: "GBIF Backbone Taxonomy v2024-11"
total_records: 127
geographic_extent: "California coastal range"
temporal_extent: "1987-2010"
transformations:
  - Split plot and observation data from single table
  - Standardized species names against GBIF
  - Converted coordinates from DMS to decimal degrees
  - Assigned 50m coordinate uncertainty to historical records
```

---

## PART 4: FILE STRUCTURE ASSUMPTIONS & JOIN LOGIC

### Expected Input File Structures

The app assumes (but validates) this general structure:

#### File 1: Plot/Survey Metadata
```csv
plotID,  date,        plotSize_m2, samplingProtocol,      recordedBy,  eventRemarks
P001,    2010-05-15,  100,         "30-minute plot walk", "J. Smith",  "Coastal scrub survey"
P002,    2010-05-16,  100,         "30-minute plot walk", "J. Smith",  "Oak woodland"
```
**Purpose:** One row per survey unit  
**Primary Key:** plotID  
**Role in Join:** Provides survey-level metadata (sampling effort, date, protocol)

#### File 2: Location/Site Reference Data
```csv
siteID,  siteName,          lat,      lon,       elevation_m, habitat_type
S001,    "Cypress Point",   36.582,   -121.939,  50,          "coastal_scrub"
S002,    "Oak Ridge",       36.650,   -121.850,  800,         "oak_woodland"
```
**Purpose:** One row per site/location  
**Primary Key:** siteID  
**Role in Join:** Provides geographic and habitat context  
**Linking to plots:** plots.siteID = locations.siteID

#### File 3: Species Observations
```csv
occurrenceID,   plotID, scientificName,    individualCount, notes
OCC_P001_001,   P001,   "Abies bracteata", 2,               "small saplings"
OCC_P001_002,   P001,   "Pinus ponderosa", 5,               "mixed sizes"
OCC_P002_001,   P002,   "Quercus agrifolia", 1,             "mature tree"
```
**Purpose:** One row per observation  
**Primary Key:** occurrenceID  
**Foreign Key:** plotID  
**Role in Join:** Core observation records; links to plots via plotID

#### File 4 (Optional): Trait or Abundance Data
```csv
occurrenceID,    traitName,      value, unit
OCC_P001_001,    "height_m",     2.5,   "meters"
OCC_P001_002,    "diameter_cm",  15,    "cm"
```
**Purpose:** Additional measurements tied to individual observations  
**Foreign Key:** occurrenceID  

### Join Logic

**Default Join Strategy:**

```
SELECT 
  o.occurrenceID,
  o.scientificName,
  o.individualCount,
  p.plotID,
  p.date AS eventDate,
  p.samplingProtocol,
  p.samplingEffort,
  p.recordedBy,
  l.siteID,
  l.siteName,
  l.lat AS decimalLatitude,
  l.lon AS decimalLongitude,
  l.elevation_m,
  l.habitat_type

FROM observations o
LEFT JOIN plots p ON o.plotID = p.plotID
LEFT JOIN locations l ON p.siteID = l.siteID
LEFT JOIN traits t ON o.occurrenceID = t.occurrenceID
```

**Validation After Join:**
- [ ] Row count unchanged (0 total losses)
- [ ] All plotIDs matched (if any orphaned, show count)
- [ ] All siteIDs matched (if any orphaned, show count)
- [ ] No duplicate occurrenceIDs introduced

**User Feedback:**
```
Join Result
───────────
✓ 127 observations matched to 15 plots (0 orphaned)
✓ 15 plots matched to 8 sites (0 orphaned)
✓ No duplicate records introduced
Result: 1 occurrence per row, all metadata present
```

---

## PART 5: PROPOSED UI LAYOUT & USER FLOWS

### Overall App Layout (Using bs4Dash)

```
┌─────────────────────────────────────────────────────────────────┐
│ BIEN Historical Data Ingest                              < > ≡  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│ ┌─────────────────────┐  ┌────────────────────────────────────┐ │
│ │                     │  │ Step 1: Upload Files               │ │
│ │ Sidebar Menu        │  │ ─────────────────────────────────  │ │
│ │                     │  │                                    │ │
│ │ ▶ Upload            │  │ [👆 Drop files here or select]    │ │
│ │ ▶ Link Files        │  │                                    │ │
│ │ ▶ Schema Mapping    │  │ [Process Files]                   │ │
│ │ ▶ Taxonomy          │  │                                    │ │
│ │ ▶ Validation        │  │ Files: 3 uploaded ✓               │ │
│ │ ▶ Review & Export   │  │ • plot_metadata.csv (15 rows)     │ │
│ │ ▶ Help              │  │ • locations.csv (8 rows)          │ │
│ │                     │  │ • observations.csv (127 rows)     │ │
│ │                     │  │                                    │ │
│ │                     │  │ [Preview ▼]                       │ │
│ └─────────────────────┘  └────────────────────────────────────┘ │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Visual Flow

#### Upload → Preview
```
[Upload]
    ↓
[Process]
    ↓
[Show file summary table]
    ├─ Filename
    ├─ Format
    ├─ Rows/Cols
    └─ [Expand to preview]
```

#### Link → Join Preview
```
[Select primary table] → observations
    ↓
[Detect foreign keys]
    ├─ "observations.plotID" matches "plots.plotID" ← Suggest this
    └─ "plots.siteID" matches "locations.siteID" ← Suggest this
    ↓
[Preview joined result]
    └─ Show 50 rows with all matched columns
```

#### Schema Mapping → Validation
```
[Darwin Core Required Fields]
    ├─ occurrenceID    → [observations.occurrenceID] ✓
    ├─ scientificName  → [observations.scientificName] ✓
    ├─ eventDate       → [plots.date] ✓
    ├─ decimalLatitude → [locations.lat] ✓
    ├─ decimalLongitude → [locations.lon] ✓
    └─ basisOfRecord   → [← SELECT] (required)
    ↓
[Optional Fields] (collapse-able)
    ├─ coordinateUncertaintyInMeters → (not mapped)
    ├─ samplingEffort → [plots.samplingSeconds] ✓
    └─ ...
    ↓
[All required fields mapped] ✓
```

#### Taxonomy → Results
```
[Check Species Names]
    ↓
[GBIF API lookup]
    ↓
[Show reconciliation results]
    ├─ ✓ Exact: 18 names
    ├─ ⚠ Fuzzy: 1 name (user review required)
    └─ ✗ Unresolved: 1 name
    ↓
[Show unresolved names with suggestions]
    ├─ Your: "Abies sp."
    ├─ Suggestion: Click to resolve or skip
    └─ Decision: [Accept] [Reject] [Manual Entry]
```

#### Validation → Issues by Tier
```
[Run Validation]
    ↓
[Tier 1: BLOCKING ERRORS]
    ├─ ✗ 5 occurrences with missing coordinates
    ├─ ✗ 2 invalid dates (format error)
    └─ ✗ 1 duplicate occurrenceID
    ↓
[Tier 2: WARNINGS]
    ├─ ⚠ 12 records with high coordinate uncertainty
    ├─ ⚠ 5 records with abundance but no sampling effort
    └─ ⚠ 2 potential duplicate records (same location, date, species)
    ↓
[Tier 3: INFORMATION]
    ├─ ℹ 127 records total
    ├─ ℹ Geographic span: 300 km
    └─ ℹ Temporal span: 25 years
    ↓
[Severity: Can't proceed until Tier 1 resolved]
```

#### Review & Export
```
[Summary Statistics]
    ├─ Dataset: 127 observations, 15 plots, 8 sites
    ├─ Geography: Coastal range (CA)
    ├─ Temporal: 1987-2010
    └─ Quality: 0 blocking errors, 2 unresolved warnings
    ↓
[Complete Metadata]
    ├─ Dataset Name: [Smith et al. 2010 Coastal Vegetation]
    ├─ Citation: [DOI: 10.1111/...]
    ├─ License: [CC-BY-4.0 ▼]
    └─ Notes: [Optional transformation notes]
    ↓
[Download]
    ├─ [📥 darwin_core_export.tsv]
    └─ [📥 metadata.yaml]
    ↓
[Next: Upload to BIEN portal (benquist.shinyapps.io/bien-submit/)]
```

---

## PART 6: BIEN SCHEMA MAPPING STRATEGY

### Darwin Core → Ecologist Communication

**Challenge:** Darwin Core is designed for data repositories, not ecologists.  
**Solution:** Map Darwin Core fields to ecologist-friendly categories.

| Category | Darwin Core Fields | What Ecologist Thinks | Validation |
|----------|-------------------|----------------------|------------|
| **What was observed?** | scientificName, taxonRank, identifiedBy | "Which species and who identified it?" | Name reconciliation + backbone match |
| **Where?** | decimalLatitude, decimalLongitude, coordinateUncertaintyInMeters, locality | "GPS coordinates (and how accurate?)" | Coordinate bounds + uncertainty check |
| **When?** | eventDate | "What date was this observed?" | ISO 8601 format + date validity |
| **How much?** | individualCount, samplingEffort | "How many individuals? How hard did we look?" | Consistency between count and effort |
| **How was it observed?** | basisOfRecord, samplingProtocol | "Was this a specimen, iNat photo,  field observation, or literature record?" | Controlled vocabulary |
| **Survey context** | eventID, samplingProtocol, eventRemarks | "Was this in a plot? What size? Notes?" | Foreign key join to plot table |
| **Who cares?** | recordedBy, institutionCode, collectionCode | "Who collected this? Which herbarium?" | Provenance tracking |

### Required-to-Optional Mapping Guidance

**MUST HAVE (validate strictly):**
- scientificName (will reconcile against GBIF)
- eventDate (ISO 8601 required)
- decimalLatitude + decimalLongitude (coordinate validation)
- basisOfRecord (PreservedSpecimen, Observation, Literature, etc.)

**CRITICAL IF MEANINGFUL DATA PRESENT:**
- samplingEffort (if individualCount > 0)
- coordinateUncertaintyInMeters (especially for historical loc data)
- samplingProtocol (helps interpret record type)

**SHOULD HAVE:**
- recordedBy (supports provenance)
- eventID or plotID (links to survey metadata)
- eventRemarks (notes on collection)

**NICE TO HAVE:**
- identifiedBy (who confirmed the ID)
- occurrenceRemarks (notes on this record)
- datasetName, accessRights (metadata)

### Handling Multi-Table Data → Flat Darwin Core

**Problem:** Plot, site, and observation data live in separate tables; Darwin Core wants flat rows.

**Solution:** Pre-join all tables, then map flattened columns.

```
Raw Structure:
  Observations Table: occurrenceID, plotID, scientificName, individualCount
  Plots Table: plotID, date, samplingEffort, recordedBy
  Locations Table: siteID, lat, lon, elevation

Step 1: Join observations ← plots ← locations
Step 2: Result is one wide row per observation with all metadata
Step 3: Select which columns map to Darwin Core

Example Row After Join:
  occurrenceID | plotID | scientificName | individualCount | date | samplingEffort | recordedBy | lat | lon | elevation | ...
  OCC_001      | P001   | Abies bracteata | 2             | 2010-05-15 | 30 minutes  | J. Smith | 36.582 | -121.939 | 50 | ...
```

---

## PART 7: DATA VALIDATION CHECKLIST

### Priority-Ordered Validation Rules

**TIER 1: BLOCKING — Must fix to proceed**

| Check | Rule | Error Message | Fix |
|-------|------|---------------|-----|
| ocurrenceID present | Every row must have non-empty occurrenceID | "Missing occurrenceID in X rows" | Go back, add unique IDs |
| scientificName present | Every row must have non-empty name | "Missing scientificName in X rows" | Add species names |
| eventDate present | Every row must have a date | "Missing eventDate in X rows" | Add observation dates |
| eventDate valid | Format must be ISO 8601 YYYY-MM-DD | "Y dates invalid format" | Reformat dates |
| Latitude present | Non-empty decimalLatitude (or coarse location) | "Missing coordinates in X rows" | Add decimal lat/lon |
| Longitude present | Non-empty decimalLongitude | "Missing coordinates in X rows" | Add decimal lat/lon |
| Latitude range | -90 ≤ lat ≤ 90 | "X latitudes out of range" | Check hemisphere |
| Longitude range | -180 ≤ lon ≤ 180 | "X longitudes out of range" | Check hemisphere |
| basisOfRecord present | One of: PreservedSpecimen, Observation, Literature, etc. | "Missing or invalid basisOfRecord" | Specify record type |
| occurrenceID unique | No duplicate IDs in this submission | "X duplicate occurrenceIDs found" | Resolve duplicates |

**TIER 2: WARNINGS — Should address**

| Check | Rule | Warning | Action |
|-------|------|---------|--------|
| Coordinate precision | coordinateUncertaintyInMeters > 5000m | "Coarse coordinates (>5km uncertainty)\nRecords may not be suitable for modeling" | Mark as low-precision; note reason |
| Coordinate suspicion | Lat=0, Lon=0 or other obvious placeholders | "Possible placeholder coordinates detected\nContinues?" | Confirm OK or replace |
| Date suspicion | eventDate pre-dates species description or is >100 years old | "Historical date (pre-1900?) — verify correct\nRecords may have been misidentified over time" | Confirm OK or update |
| Abundance without effort | individualCount > 0 but no samplingEffort | "Abundance recorded but sampling effort undefined\nMakes interpretation ambiguous" | Add sampling effort or remove count |
| Name not resolved | Species name didn't match GBIF exactly | "X names required fuzzy match or manual review\nAccept as-is?" | Resolve or document |
| Potential duplicate | Multiple records at identical lat/lon, date, species | "X possible duplicate records\nSame observation recorded twice?" | Remove duplicates or confirm distinct |
| Foreign key issues | plotID referenced but no matching plot metadata | "X orphaned observations (plotID not found)\nData links incomplete?" | Add missing plots or remove refs |

**TIER 3: INFORMATION — Useful to know**

| Check | Rule | Message | Note |
|--------|------|---------|------|
| Record count | Summary | "127 total observations in this submission" | Informational |
| Geographic extent | Bounding box | "Geographic range: 50-300 km, covers CA coastal range" | Helps interpret data |
| Temporal extent | Date range | "Records span 1987-2010 (23 years)" | Helps interpret historical variability |
| Infraspecific ranks | Presence of subspecies, var., form | "3 names include subspecific ranks (e.g., subsp.)" | Acceptable; will be reconciled |
| Author in name | Presence of author string in scientificName | "5 names include author (e.g., '(Nutt.) Kochvar.')\nWill be parsed during reconciliation" | Acceptable; auto-parsed |
| Missing coordinateUncertaintyInMeters | Option not mapped | "coordinateUncertaintyInMeters not provided\nAll records will be flagged as high uncertainty" | Informational; OK if accepted |

---

## PART 8: PROTOTYPE CODE STRUCTURE

The prototype (`app_redesign_prototype.R`) is provided with the following key components:

### Key Modules

**1. Upload Module**
- Accepts multi-file input (CSV, XLSX)
- Detects format automatically
- Shows file summary + preview
- Extracts column names and data types

**2. Link Module**
- Analyzes column names across files
- Suggests foreign key matches (e.g., `observations.plotID` ↔ `plots.plotID`)
- Allows user to confirm or modify joins
- Performs LEFT JOINs to flatten data
- Validates join results (orphaned rows detected)

**3. Schema Mapping Module**
- Displays Darwin Core required fields with descriptions
- Allows dropdown selection of corresponding user columns
- Shows mapping summary table
- Validates all required fields mapped before proceeding

**4. Taxonomy Resolution Module**
- Extracts unique species names
- Queries GBIF Backbone API (cached for performance)
- Classifies results: exact, fuzzy, unresolved
- Displays reconciliation table with columns:
  - input_name (user provided)
  - matched_name (from backbone)
  - status (accepted/synonym/fuzzy/unresolved)
  - confidence (0-1)

**5. Validation Module**
- Runs tiered checks (Tier 1/2/3)
- Returns issues organized by severity
- Maps coordinates for spatial inspection
- Allows user to review and decide on severity

**6. Export Module**
- Collects final metadata (dataset name, citation, license)
- Exports Darwin Core TSV formatted for BIEN submission
- Exports metadata YAML with provenance
- Provides download links

### Utility Functions

```r
# Field definitions
darwin_core_spec <- list(
  required = c(...),
  optional = c(...),
  vocabulary = list(...)
)

# Validation functions
validate_coordinates()
validate_dates()
detect_join_keys()  # Auto-detect foreign key columns
```

---

## PART 9: IMPLEMENTATION PRIORITIES

### MVP (Minimum Viable Product) — Weeks 1-2

**Must Include:**
1. ✅ Upload module with file preview
2. ✅ File linking interface (join detection)
3. ✅ Schema mapping interface
4. ✅ Basic validation (blocking errors only)
5. ✅ Darwin Core TSV export

**Why MVP First?**
- Core workflow complete end-to-end
- Real ecologists can test with actual data
- Gets feedback early

### Phase 2 (Enhanced) — Weeks 3-4

**Add:**
1. 🔄 Taxonomy resolution (GBIF API integration)
2. 🗺️ Coordinate mapping visualization
3. ⚠️ Warning-level validation (Tier 2)
4. 📝 Metadata YAML export
5. 📋 Reconciliation audit table download

**Why Phase 2?**
- Handles real pain point (species name confusion)
- Better validation catches issues earlier
- Metadata export enables reproducibility

### Phase 3 (Polish) — Weeks 5-6

**Add:**
1. 🎨 Modern UI with bs4Dash / fresh styling
2. 🚀 Performance optimization (caching, parallel joins)
3. 📚 Help documentation built into app
4. 🔒 Data privacy (mark as "draft" before final submission)
5. 💾 Save/resume workflow (user can save progress)

**Why Phase 3?**
- Improved UX makes app more discoverable
- Performance matters at scale (1000+ records)
- Users can iterate if needed

### Nice-to-Have (Future)

- **Abundance standardization** — Convert "few" → individual count ranges
- **Trait data handling** — Dedicated UI for trait measurements
- **Batch submission** — APIs to BIEN portal (currently manual)
- **Data visualization** — Historical trend plots, species accumulation
- **Feedback loop** — See what happens downstream on BIEN if data is accepted

---

## PART 10: ECOLOGIST PAIN POINTS → SOLUTION MAPPING

| Ecologist Pain Point | Current App | New App Solution | Impact |
|----------------------|-------------|------------------|--------|
| "I have 3 spreadsheets; how do I combine them?" | No support | Step 2: Link Files detects joins automatically | **Critical** — enables multi-file workflow |
| "What the heck is Darwin Core?" | No guidance | Steps 3-6: Progressive teaching of schema + live feedback | **Critical** — reduces cognitive load |
| "Are my species names right?" | No checking | Step 4: GBIF reconciliation with visual audit trail | **High** — prevents downstream taxonomy issues |
| "How do I know if my data is correct?" | No validation | Step 5: Tiered validation finds issues before submission | **High** — catches errors early |
| "I used GPS coordinates from 1987; are they good?" | No evaluation | Step 5: Flags coordinate uncertainty; shows coarse locations | **Medium** — supports decision-making |
| "Did I lose data when joining tables?" | N/A | Step 2: Validates join integrity; reports orphaned rows | **Medium** — prevents silent data loss |
| "How do I export this for BIEN?" | No export | Step 6: Darwin Core TSV ready to submit | **High** — removes guesswork |
| "I need to track what transformations I made" | No provenance | Step 6: Metadata YAML documents all decisions + dates | **Medium** — supports reproducibility |
| "My publications had different formats" | No support | App handles CSV/XLSX; auto-detects types | **Low** — convenience |
| "Can I save my progress?" | No | Future: Save/resume workflow between sessions | **Low** — nice-to-have for long projects |

---

## PART 11: TECHNICAL ARCHITECTURE

### Dependencies

**Core:**
- Shiny (UI framework)
- dplyr (data manipulation)
- tidyr (reshaping)
- stringr (text processing)

**File I/O:**
- readxl (Excel import)
- data.table::fread (CSV import)

**UI/UX:**
- bs4Dash (modern dashboard)
- fresh (theming)
- shinyFeedback (validation messages)
- shinyFiles (file picker with drag-drop)

**Validation & Taxonomy:**
- sp / sf (spatial validation if needed)
- httr + jsonlite (GBIF API calls)
- lubridate (date parsing)

**Tables & Visualization:**
- DT (data tables with sorting/filtering)
- leaflet (maps)
- ggplot2 (plots if needed)

### Performance Considerations

**Caching Strategy:**
- Cache GBIF lookups per species name (avoid repeated API calls)
- Store taxonomy reconciliation results in session for audit trail
- Pre-compute join results once, display in reactive

**Scalability:**
- MVP: Tested with ~500 records
- Phase 2: Optimize for 5,000+ records (parallel joining)
- Consider lazy loading for large previews (DT pagination)

### Data Privacy

- No data persisted to disk (except download-on-demand)
- All processing in-memory within R session
- User controls export; nothing auto-uploaded
- Option to mark submission as "draft" before final BIEN upload

---

## PART 12: SUCCESS CRITERIA

### Usability Metrics

✅ **Workflow Completion** — 80% of testers complete all 6 steps without guidance  
✅ **Time to Submit** — Average <45 minutes from upload to Darwin Core export  
✅ **Error Resolution** — Users resolve >90% of validation issues without external help  
✅ **Species Reconciliation** — >95% of names reconciled (exact + fuzzy) without manual override  

### Data Quality Metrics

✅ **Coordinate Validity** — 100% of exported coordinates pass bounds checks  
✅ **Date Validity** — 100% of exported dates in ISO 8601 format  
✅ **Schema Compliance** — 100% of exports pass Darwin Core validation  
✅ **Duplicate Detection** — Zero duplicate occurrenceIDs in exports  

### Adoption Metrics

✅ **Target Users** — 10+ ecology projects submit via app in first 3 months  
✅ **Publication Credit** — Data traced back to app in acknowledgments/methods  
✅ **Support Tickets** — <5 support questions per month (app is self-explanatory)  

---

## PART 13: KNOWN LIMITATIONS & FUTURE WORK

### Current Limitations

1. **Taxonomy:** Only GBIF Backbone v2024-11; future versions need update mechanism
2. **Coordinate Uncertainty:** Assumes user provides; doesn't auto-assign based on GPS model
3. **Abundance Interpretation:** No standardization of "few", "common", "rare" → counts
4. **Trait Data:** Basic support; not optimized for complex trait relationships
5. **Historical Metadata:** Doesn't auto-extract publication metadata from DOI
6. **Non-English Names:** May struggle with scientific names in non-Latin scripts

### Would Enable Future Work

1. **Batch Import:** APIs to pull data from ARPHA, Symbiota, iDigBio
2. **Downstream Tracking:** Integration with BIEN portal; track submission status
3. **Feedback Loop:** "Your data was rejected because..." → app suggests fixes
4. **Collaborative Review:** Share draft submissions with colleagues before final submit
5. **Template Creation:** "Save this workflow as template" for similar projects
6. **ML-Assisted Reconciliation:** Train model on user's historical decisions

---

## PART 14: IMPLEMENTATION CHECKLIST

### Phase 1: Core Functionality

- [ ] Create Shiny app scaffold with 6-tab layout
- [ ] Implement upload module (multi-file, format detection)
- [ ] Implement link module (foreign key detection, join preview)
- [ ] Implement schema module (field selection, validation)
- [ ] Implement validation module (Tier 1 checks)
- [ ] Implement export module (Darwin Core TSV + metadata YAML)
- [ ] Test with 3-5 real ecology datasets
- [ ] Deploy to shinyapps.io

### Phase 2: Taxonomy + Advanced Validation

- [ ] Integrate GBIF Backbone API with caching
- [ ] Implement taxonomy reconciliation UI
- [ ] Add Tier 2 validation checks (warnings)
- [ ] Add coordinate mapping visualization
- [ ] Test with species name variations
- [ ] Create taxonomy audit trail export

### Phase 3: UX Polish + Docs

- [ ] Refresh UI with bs4Dash + modern color scheme
- [ ] Write user guide / tutorial
- [ ] Add in-app help tooltips
- [ ] Optimize for performance (1000+ records)
- [ ] User acceptance testing with target ecologists
- [ ] Final deployment + announcement

---

## CONCLUSION

This redesign transforms the BIEN Shiny app from a **data browser** into a **data ingestion and validation platform**. By guiding ecologists through a step-by-step workflow with smart automation (file linking, schema mapping, taxonomy reconciliation, quality checks), we make it dramatically easier to submit historical observation data to BIEN.

**Key Innovation:** The app meets ecologists where they are (messy multi-file data) and progressively transforms that data into publication-ready Darwin Core format, with full provenance and audit trail.

**Expected Outcome:** More high-quality,  well-documented historical observation data flowing into BIEN, reducing friction between publication and data submission.

---

**Next Steps:**
1. Review with biodiversity science and ecology teams
2. Prototype with 2-3 "test" datasets from recent publications
3. Gather feedback from target users (ecologists, BIEN curation team)
4. Refine design based on feedback
5. Begin Phase 1 implementation
