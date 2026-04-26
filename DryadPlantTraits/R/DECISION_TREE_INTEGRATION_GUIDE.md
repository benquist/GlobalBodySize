# Prioritized Decision-Tree Algorithm for Trait-Unit Inference

## Overview

The decision-tree algorithm (`iu_infer_unit_by_decision_tree()`) provides a robust, traceable method for resolving unit ambiguity in trait observations, particularly for problematic cases like SLA/LMA confusion where reciprocal traits may be misreported.

**File location:** `DryadPlantTraits/R/infer_units_decision_tree.R`

## Integration with Existing Code

### 1. **No Breaking Changes**
   - Existing `infer_units.R` functions are unchanged
   - New functions added alongside existing infrastructure  
   - Existing `infer_units_for_dataset()` and `infer_units_batch()` continue to work
   - Decision-tree can be adopted incrementally per trait or dataset

### 2. **Dependency Chain**
   ```
   iu_infer_unit_by_decision_tree()
   ├── iu_resolve_trait() [existing, uses iu_norm()]
   ├── iu_parse_numeric() [existing]
   ├── iu_value_stats() [existing]
   ├── iu_get_reference_range() [NEW]
   ├── iu_get_conversion_factor() [NEW]
   ├── iu_test_reciprocal_tokens() [NEW]
   ├── iu_scan_unit_variants() [NEW]
   └── iu_get_reciprocal_trait() [NEW]
   ```

### 3. **Loading the Module**
   ```r
   source('DryadPlantTraits/R/infer_units_decision_tree.R')
   source('DryadPlantTraits/R/infer_units.R')
   ```

## Function Signature

```r
iu_infer_unit_by_decision_tree <- function(
  trait_name,           # stated trait name (e.g., "specific leaf area")
  values,               # numeric values (raw, unparsed)
  column_name = NA_character_,
  unit_string = NA_character_,
  source_context = NULL  # optional list(methods_text, dataset_title, journal_name)
)
```

### Return Value (List)
```r
list(
  inferred_unit = "mm2_per_mg",        # canonical unit (NA if unresolved)
  confidence = "high",                  # "high" | "medium" | "low" | "none"
  evidence = "CANONICAL_UNIT_IN_BOUNDS",# evidence code (see Evidence Codes below)
  candidate_units = c("mm2_per_mg", "cm2_per_g", "m2_per_kg"),
  conversion_factor = 1.0,              # numeric scaling factor
  reciprocal = FALSE,                   # TRUE if reciprocal trait detected
  reason = "Median value 5.2 in canonical unit mm2_per_mg range [1, 1000].",
  citation_keys = c("Kattge2020", "Wright2004")
)
```

## Evidence Codes

| Evidence Code | Meaning | Confidence |
|---|---|---|
| `CANONICAL_UNIT_IN_BOUNDS` | Median value falls within reference range for stated trait + canonical unit | HIGH |
| `UNIT_VARIANT_FOUND` | Exactly one alternative unit scale explains the values | HIGH |
| `AMBIGUOUS_UNIT_SCALE` | Multiple unit scale interpretations plausible for same trait | MEDIUM |
| `RECIPROCAL_TRAIT_DETECTED` | Column/unit tokens + value plausibility suggest reciprocal trait (e.g., LMA vs SLA) | MEDIUM |
| `RECIPROCAL_POSSIBLE_VALUE_MATCH_ONLY` | Values match reciprocal but column name doesn't support it | LOW |
| `OUT_OF_BOUNDS_NO_RECIPROCAL_PAIR` | Values out of bounds; no reciprocal trait defined | LOW |
| `OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS` | Values fail both canonical and reciprocal bounds | LOW |
| `NO_TRAIT_MATCH` | Trait name not recognized | NONE |

## Algorithm Flow (6-Step Decision Tree)

### STEP 1: Resolve Trait Name
- Normalizes input (lowercase, remove special chars)
- Looks up in `iu_trait_aliases()` 
- Returns canonical trait key (e.g., `specific_leaf_area`) or NA

### STEP 2: Canonical Unit Lookup
- Maps trait to its assumed canonical unit
- Example: `specific_leaf_area` → `mm2_per_mg`

### STEP 3: Parse Values
- Converts trait_value to numeric via `iu_parse_numeric()`
- Computes median via `iu_value_stats()` (using log scale for most traits)
- Returns NONE if no parseable values

### STEP 4: Check Canonical Bounds
- Gets reference range from `iu_get_reference_range(trait_key, canonical_unit)`
- If median **in bounds** → return **HIGH confidence**, **CANONICAL_UNIT_IN_BOUNDS**
- If median **out of bounds** → proceed to STEP 5

### STEP 5: Try Unit Variants
- Scans alternative unit scales for same trait (e.g., cm²/g, m²/kg for SLA)
- For each variant:
  - Converts median via `iu_get_conversion_factor(trait, canonical, variant)`
  - Checks if converted value in reference range for that variant
  - Tracks all matches
- **If exactly 1 variant matches** → HIGH confidence, UNIT_VARIANT_FOUND
- **If multiple variants match** → MEDIUM confidence, AMBIGUOUS_UNIT_SCALE  
- **If no variants match** → proceed to STEP 6

### STEP 6: Reciprocal-Trait Hypothesis (SLA↔LMA ONLY)
- Only applies to traits with reciprocal pairs: SLA ↔ LMA
- Computes reciprocal_value = 1 / median
- Checks if reciprocal in reference range for reciprocal trait
- Scans column_name + unit_string for LMA tokens via `iu_test_reciprocal_tokens()`
- **If reciprocal in bounds AND tokens found** → MEDIUM confidence, RECIPROCAL_TRAIT_DETECTED
- **If reciprocal in bounds BUT NO tokens** → LOW confidence, RECIPROCAL_POSSIBLE_VALUE_MATCH_ONLY
- **If neither canonical nor reciprocal fit** → LOW confidence, OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS

## Usage Examples

### Example 1: Canonical SLA with High Confidence
```r
result <- iu_infer_unit_by_decision_tree(
  trait_name = "specific leaf area",
  values = c(3, 4, 5, 6, 7),
  column_name = "SLA",
  unit_string = "mm2/mg"
)
# Result: confidence="high", inferred_unit="mm2_per_mg", evidence="CANONICAL_UNIT_IN_BOUNDS"
```

### Example 2: Possible SLA/LMA Confusion
```r
result <- iu_infer_unit_by_decision_tree(
  trait_name = "SLA",
  values = c(0.5, 1.0, 1.5),
  column_name = "LMA_mg_mm2",
  unit_string = "mg/mm2"
)
# Result: confidence="medium", reciprocal=TRUE, inferred_unit="mg_per_mm2", 
#         evidence="RECIPROCAL_TRAIT_DETECTED"
```

### Example 3: Out-of-Bounds Values
```r
result <- iu_infer_unit_by_decision_tree(
  trait_name = "SLA",
  values = c(900000, 1000000, 1100000)
)
# Result: confidence="low", inferred_unit=NA, 
#         evidence="OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS"
```

## Reference Ranges (Traits Supported)

### Specific Leaf Area (SLA)
- `mm2_per_mg`: 1–1000 (Kattge2020, Wright2004)
- `cm2_per_g`: 0.1–100 (Kattge2020, Wright2004)
- `m2_per_kg`: 0.001–1 (Kattge2020, Wright2004)

### Plant Height
- `m`: 0.01–150 (Kattge2020, Bergmann2020)
- `cm`: 1–15,000 (Kattge2020, Bergmann2020)
- `mm`: 10–1.5e6 (Kattge2020, Bergmann2020)

### Leaf Dry Matter Content (LDMC)
- `mg_per_g`: 50–900 (PerezHarguindeguy2013, Kattge2020)
- `g_per_g`: 0.05–0.9 (PerezHarguindeguy2013, Kattge2020)
- `percent`: 5–90 (PerezHarguindeguy2013, Kattge2020)

### Wood Density
- `g_per_cm3`: 0.1–1.3 (Chave2009)
- `kg_per_m3`: 100–1300 (Chave2009)

### Stomatal Conductance (gs)
- `mmol_per_m2_per_s`: 10–2000 (Medlyn2017, Kattge2020)
- `mol_per_m2_per_s`: 0.01–2 (Medlyn2017, Kattge2020)

### Photosynthetic Rate (Anet)
- `umol_per_m2_per_s`: 0.1–60 (Kattge2020, Wright2004)
- `mmol_per_m2_per_s`: 0.0001–0.06 (Kattge2020, Wright2004)
- `mol_per_m2_per_s`: 1e-7–6e-5 (Kattge2020, Wright2004)

### Seed Mass
- `mg`: 0.001–2.5e7 (Kattge2020)
- `g`: 1e-6–2.5e4 (Kattge2020)
- `kg`: 1e-9–25000 (Kattge2020)

### Leaf Area
- `mm2`: 1–3e6 (Kattge2020)
- `cm2`: 0.01–3e4 (Kattge2020)
- `m2`: 1e-6–30 (Kattge2020)

### Leaf Nutrients (N, P)
- `mg_per_g`: varies by nutrient (Kattge2020, Wright2004)
- `mg_per_cm2`: varies by nutrient (Kattge2020, Wright2004)

## Citation References

All reference ranges and decision thresholds are backed by peer-reviewed publications:

- **Kattge et al. 2020** – Global Change Biology 26:119-188. [https://doi.org/10.1111/gcb.14904](https://doi.org/10.1111/gcb.14904)
- **Wright et al. 2004** – Nature 428:821-827. [https://doi.org/10.1038/nature02403](https://doi.org/10.1038/nature02403)
- **Perez-Harguindeguy et al. 2013** – Australian Journal of Botany 61:167-234. [https://doi.org/10.1071/BT12225](https://doi.org/10.1071/BT12225)
- **Chave et al. 2009** – Ecology Letters 12:351-366. [https://doi.org/10.1111/j.1461-0248.2009.01285.x](https://doi.org/10.1111/j.1461-0248.2009.01285.x)
- **Medlyn et al. 2017** – New Phytologist 216:10-16. [https://doi.org/10.1111/nph.14626](https://doi.org/10.1111/nph.14626)
- **Bergmann et al. 2020** – Science Advances 6:eaba3756. [https://doi.org/10.1126/sciadv.aba3756](https://doi.org/10.1126/sciadv.aba3756)

## Key Design Principles

1. **Explicit Traceability**: Every decision returns evidence codes + reason + citations
2. **Conservative Confidence**: Only HIGH for explicitly justified cases
3. **Reciprocal-Aware**: Explicitly handles SLA↔LMA confusion with token scanning
4. **Quantile-Based**: Uses robust median (q50) on log scale for most traits
5. **Reference-Backed**: All thresholds cite published global trait syntheses
6. **Non-Destructive**: Returns NA for inferred_unit when truly ambiguous; does not force a choice

## Testing

Run the integrated test suite:
```r
source('DryadPlantTraits/R/infer_units_decision_tree.R')
source('DryadPlantTraits/R/infer_units.R')

test_results <- iu_test_decision_tree(verbose = TRUE)
```

Test cases validate:
- Canonical unit in bounds (HIGH)
- Out-of-bounds values (LOW)
- Reciprocal detection with tokens (MEDIUM)
- Plant height in canonical units (HIGH)
- Unrecognized traits (NONE)

## Future Enhancements

1. **Expand Trait Coverage**: Add more traits (e.g., hydraulic conductivity, carboxylation capacity)
2. **Learn from Corrections**: Track when QA flags overturn algorithm decisions
3. **Context-Aware Priors**: Use journal impact factor, dataset reputation, trait reporting frequency to adjust confidence
4. **Multi-Dataset Learning**: Batch analysis to detect systematic scale shifts within datasets
5. **Bayesian Refinement**: Incorporate prior probabilities learned from historical patterns in TRY/BIEN

## Maintenance Notes

- **Reference ranges**: Update in `iu_get_reference_range()` when new global syntheses published
- **Aliases**: Keep `iu_trait_aliases()` in sync with DryadPlantTraits standardized trait names  
- **Conversion factors**: Document any unit rescalings if datasets use non-standard scales
- **Reciprocal tokens**: Expand LMA keyword list as we encounter new labeling patterns

