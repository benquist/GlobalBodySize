# Species Name Reconciliation Strategy for BIEN Data Ingestion App

**Prepared by:** Taxonomy Reconciliation Specialist  
**Date:** April 2025  
**Scope:** Integration of taxonomic name resolution into the historical data submission workflow

---

## EXECUTIVE SUMMARY

This document specifies how species name reconciliation will be integrated into the data ingestion app to support BIEN submission. It addresses:

1. **Taxonomic backbone selection** (which authority to use)
2. **Name matching strategy** (exact, canonical, fuzzy, manual)
3. **UI for ecologist decision-making** (visualizing matches and conflicts)
4. **Reconciliation output** (audit-ready reconciliation table)
5. **Integration points in app workflow** (where taxonomy checking happens)

---

## SECTION 1: TAXONOMIC BACKBONE SELECTION

### Recommended Primary Backbone: GBIF Backbone Taxonomy

**Why GBIF?**
- Actively maintained and versioned (new release ~annually)
- Covers both plants, animals, fungi, microbes
- API freely available
- Widely used in biodiversity data systems
- Links to other authorities (Wikispecies, CoL, etc.)
- Version tracking ensures reproducibility

**Access Method:**
- GBIF Backbone API: `https://www.gbif.org/api/enumerations/taxonomy/lookup`
- Specification: GBIF Backbone Taxonomy v2024-11 (or latest available)
- Caching: Retain results per session to avoid duplicate API calls

### Secondary Backbones (Future Extensibility)

If user requests alternative authorities:

| Backbone | Strengths | API | Status |
|----------|-----------|-----|--------|
| **GBIF Backbone** | Comprehensive, current, well-maintained | ✓ Free API | **Recommended** |
| **Catalogue of Life (CoL)** | Authoritative synonym database; used by many publishers | ✓ Free API | Phase 2+ |
| **POWO** (Kew) | Plant-only, excellent authority for vascular plants | ✓ Free API (limited) | Phase 2+ |
| **WoRMS** | Marine organisms; formal authority | ✓ Free API | Phase 2+ |
| **NCBI Taxonomy** | Microbial + animals; used in genomics | ✓ Free API | Phase 2+ |

### Versioning & Reproducibility

**Every reconciliation must record:**
```
backbone_version: "GBIF Backbone Taxonomy v2024-11"
query_date_utc: "2025-04-15T14:32:00Z"
api_endpoint: "https://www.gbif.org/api/enumerations/taxonomy/lookup"
```

This allows future re-reconciliation against the same backbone or audit against newer versions.

---

## SECTION 2: NAME PARSING AND NORMALIZATION

### Input Name Parsing

Before querying GBIF, normalize user-entered names:

```r
normalize_binomial <- function(name) {
  # Input: "PINUS PONDEROSA", "pinus ponderosa subsp. potentior", etc.
  # Output: Standardized name with preserved metadata
  
  # Step 1: Trim whitespace
  name <- str_squish(name)
  
  # Step 2: Parse components
  parts <- strsplit(name, "\\s+")[[1]]
  
  # Step 3: Standardize capitalization
  if (length(parts) >= 1) {
    parts[1] <- str_to_title(parts[1])  # Genus: "Genus"
  }
  if (length(parts) >= 2) {
    parts[2] <- str_to_lower(parts[2])   # Species epithet: "species"
  }
  
  # Step 4: Preserve infraspecific rank markers
  # "subsp.", "var.", "f." should stay as provided
  
  # Step 5: Detect and preserve author string
  # E.g., "(Nutt.) Koch" at the end
  
  normalized <- paste(parts, collapse = " ")
  
  list(
    normalized = normalized,
    genus = parts[1],
    species = if (length(parts) >= 2) parts[2] else NA,
    infraspecific_marker = detect_rank_marker(name),
    author = extract_author(name)
  )
}
```

**Output Example:**
```
Input: "ABIES BRACTEATA (NUTT.) KOCH"
Parsed:
  normalized: "Abies bracteata"
  genus: "Abies"
  species: "bracteata"
  author: "(Nutt.) Koch"
  rank: "species"
```

### Query Strategy

Send normalized canonical name (genus + specific epithet) to GBIF:

```r
query_gbif_backbone <- function(parsed_name, timeout_sec = 5, cache_env = NULL) {
  # Query: Just canonical name
  query_string <- paste(parsed_name$genus, parsed_name$species)
  
  # Check cache first
  cache_key <- tolower(query_string)
  if (!is.null(cache_env) && exists(cache_key, envir = cache_env)) {
    return(get(cache_key, envir = cache_env))
  }
  
  # Query GBIF API
  url <- paste0(
    "https://www.gbif.org/api/enumerations/taxonomy/lookup?",
    "name=", URLencode(query_string)
  )
  
  response <- tryCatch(
    jsonlite::fromJSON(httr::GET(url, timeout(timeout_sec))$content),
    error = function(e) {
      warning(paste("GBIF API error:", e$message))
      NULL
    }
  )
  
  # Cache result
  if (!is.null(cache_env)) {
    assign(cache_key, response, envir = cache_env)
  }
  
  response
}
```

---

## SECTION 3: RECONCILIATION LOGIC AND DECISION TREE

### Matching Decision Tree

```
User enters: "Pinus ponderosa"
         ↓
Query GBIF with canonical "Pinus ponderosa"
         ↓
         ├─ EXACT MATCH FOUND (confidence = 1.0)
         │  └─ Return accepted name + accept
         │
         ├─ SYNONYM MATCH FOUND (confidence ≥ 0.95)
         │  └─ Check if homotypic (same concept) or heterotypic (renamed)
         │  └─ Map to accepted name
         │
         ├─ FUZZY MATCH(ES) FOUND (confidence 0.7-0.94)
         │  └─ User must review options
         │  └─ Mark as "requires_review"
         │
         └─ NO MATCH or LOW CONFIDENCE (< 0.7)
            └─ Mark as "unresolved"
            └─ User can provide manual name or skip
```

### Reconciliation Table Columns

Every name must have a complete reconciliation row:

```r
reconciliation_table <- data.frame(
  # Input
  input_name_verbatim = character(),          # Exactly as user provided
  input_name_normalized = character(),        # After normalization
  
  # Matching
  match_method = character(),                 # exact | synonym | fuzzy | manual | unresolved
  match_confidence = numeric(),               # 0-1; only populated if matched
  
  # GBIF Result
  matched_name = character(),                 # What GBIF found
  matched_authorship = character(),           # Author string
  matched_rank = character(),                 # species, subspecies, etc.
  matched_taxon_id = integer(),               # GBIF taxon key
  
  # Resolution
  accepted_name = character(),                # Name user/system accepted
  accepted_taxon_id = integer(),              # ID of accepted name
  synonym_type = character(),                 # homotypic | heterotypic | NA if not synonym
  
  # Decision
  decision_status = character(),              # exact | manual_override | user_confirmed | unresolved
  decision_note = character(),                # Why this decision was made
  
  # Metadata
  backbone_version = character(),             # "GBIF Backbone v2024-11"
  query_timestamp_utc = character(),          # ISO 8601 timestamp
  
  stringsAsFactors = FALSE
)
```

**Example Reconciliation Table:**

| input_name | match_method | matched_name | accepted_name | status | backbone |
|------------|--------------|--------------|---------------|--------|----------|
| Abies bracteata | exact | Abies bracteata | Abies bracteata | accepted | GBIF 2024 |
| Pinus pon | fuzzy | *Pinus ponderosa* | Pinus ponderosa | user_confirmed | GBIF 2024 |
| Sequoia semper | exact | Sequoiadendron giganteum | Sequoiadendron giganteum | synonym | GBIF 2024 |
| Quercus sp. | unresolved | (none) | (none) | unresolved | GBIF 2024 |

---

## SECTION 4: UI FOR ECOLOGIST DECISION-MAKING

### Step 4 in App Workflow: "Taxonomic Resolution"

#### Phase 4A: Automatic Reconciliation

```
[Run Check Species Names]
    ↓
[App extracts unique scientificName values]
    ↓
[GBIF API queries all names (cached)]
    ↓
[Results summary displayed]

Summary:
─────────────────────────────
✓ Exact Matches: 18/20 names
  • Pinus ponderosa (ID: 2684245)
  • Abies bracteata (ID: 2685128)
  • ... 16 more

⚠ Fuzzy Matches: 1 name (requires decision)
  • "Pinus pon" → "Pinus ponderosa" (confidence: 0.87)

✗ Unresolved: 1 name (not found)
  • "Quercus sp." — too vague for GBIF
```

#### Phase 4B: User Reviews Unresolved Names

```
Requires Your Decision:
═════════════════════════

Name 1: "Pinus pon"
─────────
Your name:     "Pinus pon"
GBIF found:    "Pinus ponderosa"
Confidence:    87% (fuzzy match based on similarity)
Action:        ○ Accept as "Pinus ponderosa"
               ○ Reject and keep as provided
               ○ Enter manual correction: [______]

Name 2: "Quercus sp."
─────────
Your name:     "Quercus sp."
GBIF found:    (no matches)
Reason:        "sp." is a placeholder, not a species name
Action:        ○ Accept as-is (will be marked as ambiguous in output)
               ○ Enter actual species name: [______]
               ○ Mark as "uncertain identification"
```

#### Phase 4C: Confidence Indicators

```
Exact Match ✓❋ (1.0 confidence)
  → Darwin Core name accepted, no further review needed
  → occurrenceID will successfully link to GBIF

Synonym ✓◆ (≥0.95 confidence)
  → Your name: "Sequoia sempervirens"
  → GBIF accepted name: "Sequoiadendron giganteum"
  → Status: Taxonomic concept changed (old name is now synonym)
  → Recommendation: Update to "Sequoiadendron giganteum"

Fuzzy Match ⚠ (0.7-0.94 confidence)
  → Your name: "Pinus pon"
  → GBIF match: "Pinus ponderosa" (87% confident based on similarity)
  → Your decision required: Confirm or override?

Unresolved ✗ (no match)
  → Your name: "Quercus sp." or "Unknown oak"
  → GBIF status: Couldn't resolve name
  → Your options: Provide complete name or mark as ambiguous
```

---

## SECTION 5: HANDLING AMBIGUITIES AND CONFLICTS

### Ambiguous Cases: When GBIF Returns Multiple Matches

```
Your name: "Pinus"

GBIF results (multiple matches):
1. Pinus L. (genus)
2. Pinus ponderosa Douglas ex P.Lawson ex Royle
3. ... 50+ other Pinus species

Confidence: Can't determine which one you meant

Recommendation:
─────────────────
This is a genus name, not a species. 
Specify one of:
• Pinus ponderosa (ponderosa pine)
• Pinus contorta (lodgepole pine)
• [Enter other species]

Or accept as genus and mark records as ambiguous.
```

### Handling Author String Variations

```
Your name: "Pinus ponderosa subsp. potentior (Lemmon ex Parl.) A.E. Murray"

GBIF queries:
1. Canonical: "Pinus ponderosa potentior"
   → Matches subspecific concept ✓
   
2. Fallback: "Pinus ponderosa"
   → Matches species (broader) ✓

Decision: Accept as "Pinus ponderosa subsp. potentior" if GBIF recognizes
Otherwise: Fall back to "Pinus ponderosa" with note "subspecific epithet not resolved"
```

### Handling Misspellings and Typos

```r
# Fuzzy matching threshold
fuzzy_match_if_similarity_gt <- 0.85

# Example: "Pnius ponderosa" (misspelled genus)
query_gbif("Pnius ponderosa")
  → No exact match
  → Check spelling distance: 1 character difference from "Pinus"
  → Suggest: "Pinus ponderosa" (confidence: 0.92 based on Levenshtein distance)
  → User decides: Accept or manual override
```

---

## SECTION 6: Reconciliation Output & Audit Trail

### Downloadable Reconciliation Table

Users can download the reconciliation results as CSV for their records:

```csv
input_name_verbatim,input_name_normalized,match_method,confidence,accepted_name,accepted_id,status,decision_note,backbone,query_date
"Pinus ponderosa","Pinus ponderosa","exact",1.0,"Pinus ponderosa",2703405,"accepted","Exact match to GBIF","GBIF 2024-11","2025-04-15"
"Pinus pon","Pinus pon","fuzzy",0.87,"Pinus ponderosa",2703405,"user_confirmed","Fuzzy match; user accepted","GBIF 2024-11","2025-04-15"
"Abies bracteata","Abies bracteata","exact",1.0,"Abies bracteata",2685128,"accepted","Exact match to GBIF","GBIF 2024-11","2025-04-15"
"Sequoia sempervirens","Sequoia sempervirens","synonym",0.99,"Sequoiadendron giganteum",2684254,"synonym_updated","Taxonomy changed; Sequoia renamed to Sequoiadendron","GBIF 2024-11","2025-04-15"
"Quercus sp.","Quercus sp.","unresolved",NA,"(unresolved)",NA,"unresolved","Genus-only name; too vague for species-level resolution","GBIF 2024-11","2025-04-15"
```

### Metadata Associated with Reconciliation

```yaml
reconciliation_metadata:
  timestamp_utc: "2025-04-15T14:32:00Z"
  backbone_authority: "GBIF Backbone Taxonomy"
  backbone_version: "2024-11"
  backbone_url: "https://www.gbif.org/dataset/d7dddf29-f638-4322-83a0-c0ce18edc38f"
  
  summary:
    total_unique_names: 20
    exact_matches: 18
    fuzzy_matches: 1
    unresolved: 1
    percent_resolved: 95.0
  
  fuzzy_match_threshold: 0.85
  user_reviewed: true
  issues_resolved: 1
  issues_remaining: 1
```

---

## SECTION 7: Integration Points in App Workflow

### When Does Taxonomy Check Run?

**Option A: Automatic (Recommended)**
- Runs automatically after Step 3 (Schema Mapping) if scientificName column is mapped
- User can skip if they want to proceed without reconciliation
- Catches issues early

**Option B: Optional (User-Initiated)**
- User clicks "Check Species Names" only if desired
- Good for users who've already reconciled externally

**Recommended: Automatic with skip option**

```
Step 3: Schema Mapping completed
    ↓
[App detects scientificName mapped to column "scientific_name"]
    ↓
[Automatically runs GBIF reconciliation]
    ↓
Results page:
    ├─ Exact matches: 18 ✓
    ├─ Fuzzy matches: 1 ⚠
    ├─ Unresolved: 1 ✗
    └─ [Options] [Review Unresolved] [Skip to Validation]
```

### Flowchart of Taxonomy Integration

```
User enters species in observations.csv
         ↓
Step 1-3: Upload, Link, Schema (scientificName mapped)
         ↓
Step 4: "Taxonomic Resolution"
    ├─ Extract unique values from scientificName column
    ├─ Normalize each name (capitalize genus, lowercase epithet)
    └─ Query GBIF for each
         ↓
         ├─ Exact/Synonym Match (95% of names)
         │  └─ Auto-accept; record decision in reconciliation table
         │
         └─ Fuzzy/Unresolved (5% of names)
            └─ Display to user
            └─ User confirms or provides manual override
            └─ Record decision + reason
         ↓
Step 5: Validation (can now validate against accepted names)
         ↓
Step 6: Export
    ├─ Darwin Core TSV uses accepted names
    ├─ Reconciliation table included for audit trail
    └─ Metadata YAML logs taxonomy backbone + version
```

---

## SECTION 8: Quality Assurance & Audit Trail

### What Gets Tracked

For each species name, record:

1. **Verbatim input** — Exactly as user provided (immutable)
2. **Normalization steps** — What transformations were applied
3. **Query method** — Exact, fuzzy, manual
4. **Backbone queried** — GBIF, CoL, etc.
5. **Backbone version** — Allows future re-validation
6. **Query timestamp** — When reconciliation happened
7. **User decision** — What user chose (accept/override/skip)
8. **Confidence scores** — How confident was the match
9. **Reasoning** — Why this decision was made

### Reproducibility

Any future user or reviewer can:
1. See which backbone was used (GBIF 2024-11)
2. Re-query against same backbone to verify
3. Upgrade to newer backbone if available
4. Identify any names that were ambiguous or fuzzy
5. Modify decisions if science evolves

---

## SECTION 9: Handling Special Cases

### Case 1: Infraspecific Names

```
Input: "Pinus ponderosa subsp. potentior"

Strategy:
1. Query full name with subspecific epithet
2. If match: Use matched subspecific name
3. If no match: Fall back to species level ("Pinus ponderosa")
4. Record both: original intention + fall-back name

Output:
  Original input: "Pinus ponderosa subsp. potentior"
  Accepted name: "Pinus ponderosa" (subspecific epithet unresolved)
  Note: "Subspecific rank not resolved in GBIF; accepted species level"
```

### Case 2: Hybrid Species

```
Input: "Quercus × macgregorii" (× indicates hybrid)

Strategy:
1. Remove hybrid marker for initial query
2. Query "Quercus macgregorii"
3. GBIF should recognize as hybrid if in backbone
4. If recognized: Keep hybrid marker in output
5. If not: Accept species and note hybrid status not confirmed

Output:
  Input: "Quercus × macgregorii"
  Match: "Quercus ×macgregorii" (with hybrid marker)
  Status: exact
```

### Case 3: Extinct or Fossil Species

```
Input: "Archaeopteryx lithographica"

Strategy:
1. Query GBIF
2. GBIF should have fossil species in backbone
3. Mark as fossil/extinct in output for reference

Note: App primarily for modern observations,
but should handle gracefully if user provides fossil data
```

### Case 4: Common Names Mixed with Scientific Names

```
Input: ["Pinus ponderosa", "ponderosa pine", "coast redwood", "Sequoiadendron giganteum"]

Strategy:
1. Detect common names (usually all lowercase, multiple words)
2. Flag: "Common name entered; cannot map to Darwin Core scientificName"
3. Suggest: "Did you mean one of these species?"
4. User must provide scientific name for submission

Output:
  ✗ "ponderosa pine" — Common name
     Possible species: Pinus ponderosa, Pinus jeffreyi
     [Select one or enter scientific name]
```

---

## SECTION 10: API Implementation Guide

### GBIF API Call Pattern

```r
# Single name lookup
gbif_lookup_single <- function(name, api_timeout = 5) {
  url <- "https://www.gbif.org/api/enumerations/taxonomy/lookup"
  
  response <- httr::GET(
    url,
    query = list(name = name, strict = "false"),
    timeout(api_timeout),
    user_agent("BIEN-HistoricalDataApp/1.0")
  )
  
  if (response$status_code != 200) {
    warning(paste("GBIF API error:", response$status_code))
    return(NULL)
  }
  
  result <- jsonlite::fromJSON(httr::content(response, "text"))
  
  # Extract key fields
  return(list(
    canonicalName = result$canonicalName,
    usageKey = result$usageKey,
    rankKey = result$rankKey,
    matchType = result$matchType,  # exact, fuzzy, higherRank, etc.
    confidence = ifelse(result$matchType == "exact", 1.0, 0.85),
    genus = result$genus,
    species = result$species
  ))
}

# Batch lookup for efficiency
gbif_lookup_batch <- function(names_vector, cache_env = new.env()) {
  results <- list()
  
  for (name in names_vector) {
    cached_result <- tryCatch(
      get(tolower(name), envir = cache_env),
      error = function(e) NULL
    )
    
    if (!is.null(cached_result)) {
      results[[name]] <- cached_result
      next
    }
    
    # Query API
    result <- gbif_lookup_single(name)
    
    # Cache for later
    assign(tolower(name), result, envir = cache_env)
    results[[name]] <- result
    
    # Polite rate limiting
    Sys.sleep(0.5)
  }
  
  return(results)
}
```

### Error Handling

```r
# Handle API timeouts, rate limiting, etc.
safe_gbif_lookup <- function(name, attempts = 2, timeout_sec = 5) {
  for (attempt in seq_len(attempts)) {
    tryCatch({
      result <- gbif_lookup_single(name, api_timeout = timeout_sec)
      return(result)
    },
    error = function(e) {
      if (attempt < attempts) {
        # Exponential backoff
        Sys.sleep(2 ^ attempt)
      } else {
        warning(paste("GBIF lookup failed after", attempts, "attempts for:", name))
        return(NULL)
      }
    })
  }
}
```

---

## SECTION 11: Testing & Validation

### Unit Tests for Name Normalization

```r
test_that("normalize_binomial handles various formats", {
  # Standard
  expect_equal(normalize_binomial("pinus ponderosa")$normalized, "Pinus ponderosa")
  
  # Uppercase
  expect_equal(normalize_binomial("PINUS PONDEROSA")$normalized, "Pinus ponderosa")
  
  # Extra whitespace
  expect_equal(normalize_binomial("  pinus   ponderosa  ")$normalized, "Pinus ponderosa")
  
  # With author
  expect_equal(
    normalize_binomial("Pinus ponderosa (Douglas ex P.Lawson) Royle")$author,
    "(Douglas ex P.Lawson) Royle"
  )
  
  # Infraspecific
  expect_equal(
    get_rank_marker("Pinus ponderosa subsp. potentior"),
    "subsp."
  )
})
```

### Integration Tests with Real Data

```r
test_that("reconciliation produces audit-ready output", {
  # Test dataset: Mix of exact, fuzzy, unresolved
  names <- c(
    "Pinus ponderosa",      # exact
    "Pinus pon",            # fuzzy
    "Quercus sp."           # unresolved
  )
  
  results <- reconcile_names(names, backbone = "gbif_2024-11")
  
  # Validate output structure
  expect_true(all(c("accepted_name", "status", "confidence") %in% names(results)))
  expect_equal(nrow(results), 3)
  
  # Validate status assignments
  expect_equal(results$status[1], "exact")
  expect_equal(results$status[2], "fuzzy")
  expect_equal(results$status[3], "unresolved")
  
  # Validate confidence scores
  expect_equal(results$confidence[1], 1.0)
  expect_true(results$confidence[2] > 0.7 && results$confidence[2] < 1.0)
  expect_na(results$confidence[3])
})
```

---

## SECTION 12: Performance Optimization

### Caching Strategy

**Session-level cache:**
```r
# Create cache on app startup
taxonomy_cache <- new.env(parent = emptyenv())

# Check cache before API call
if (name_key %in% names(taxonomy_cache)) {
  return(taxonomy_cache[[name_key]])
}

# Add to cache after API call
taxonomy_cache[[name_key]] <- result
```

**Expected cache hits:** ~90% of names on real ecological datasets (many duplicates across observations)

### Batch Processing

```r
# Instead of 127 API calls (one per observation)
# Extract unique names first
unique_names <- unique(data$scientificName)
# Now only 8-15 API calls for whole dataset
```

### Performance Benchmarks

| Task | Time | Notes |
|------|------|-------|
| Normalize 127 names | < 0.1s | String operations only |
| Query 15 unique names (GBIF) | 5-10s | API call + 0.5s rate limiting |
| Build reconciliation table | < 0.1s | Data frame operations |
| **Total for 127 obs dataset** | **10-15s** | User sees progress bar |

---

## SECTION 13: Future Enhancements

### Planned for Phase 2+

1. **Multi-backbone support**
   - User selects: GBIF, CoL, POWO, WoRMS, NCBI
   - For overlapping taxa, show conflicts and voting

2. **Synonym tracking**
   - Return full synonym chain (original name → synonym → current accepted name)
   - Useful for publication cross-referencing

3. **Rank validation**
   - Warn if subspecific name provided for dataset coded as "species only"

4. **Trait-specific backbone**
   - If trait data present, reconcile trait names against standards (BISSE, TraitBank)

5. **Manual curation queue**
   - Unresolved names saved for taxonomist review
   - Suggest OBO Match or other reconciliation tools

---

## Conclusion

This taxonomy integration strategy ensures that:
- ✅ Species names are reconciled against authoritative backbone
- ✅ Human decisions are preserved in audit trail
- ✅ Fuzzy matches and ambiguities are flagged
- ✅ Full provenance supports reproducibility and future re-reconciliation
- ✅ Ecologists understand what happened to their names and why

By embedding species name reconciliation early in the submission workflow (Step 4), the app catches taxonomy issues before validation, export, or (worst-case) BIEN rejection.

---

## References

**GBIF Backbone Taxonomy:**
- https://www.gbif.org/dataset/d7dddf29-f638-4322-83a0-c0ce18edc38f

**Darwin Core Terms:**
- https://dwc.tdwg.org/

**Taxonomic Concept Resolution:**
- Franz, N. M., & Peet, R. K. (2016). Perspectives on improving the science of species names and comparative resource testing. Discovered

*End of Document*
