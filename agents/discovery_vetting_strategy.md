# Data Source Discovery & Vetting Workflow
## A Systematic Strategy for Finding Novel Plant Trait & Occurrence Data

**Purpose:** Identify and vet high-quality, novel plant trait and georeferenced occurrence data sources that meet BIEN publication/curation standards (peer-reviewed, Darwin Core compatible, clear provenance, >100 rows, open-access).

**Scope:** Targets geographic gaps (tropics, southern hemisphere, Central Asia, North Africa) and underrepresented trait types (metabolic, hydraulic, reproductive allocation, root architecture).

**Target outcome:** Rapidly filter hundreds of potential sources down to <10 high-confidence candidates per quarterly cycle, ready for ingestion.

---

## 1. Search Strategy

### Global Academic Repositories & Meta-Registries

**Zenodo** (Open Science Framework)
- URL: `https://zenodo.org/search`
- **Trait data queries:**
  - `("plant trait" OR "plant functional trait" OR "leaf trait" OR "root trait" OR "wood density" OR "specific leaf area") AND (dataset OR filetype:csv OR filetype:xlsx)`
  - Facets: `resource_type: dataset`, `subject: botany OR ecology`, `open_access: true`, date range (last 3 years preferred)
  - API endpoint: `https://zenodo.org/api/records?q=...&type=dataset&sort=mostrecent`
- **Occurrence data queries:**
  - `("plant occurrence" OR "vascular flora" OR "herbarium" OR "checklist") AND ("Darwin Core" OR "DwC" OR coordinates OR latitude) AND (csv OR xlsx OR dwc-a)`
  - Filter: open_access, date range
- **API batch download:** `https://zenodo.org/api/records?q={query}&size=100&page={n}`
- **Advantage:** Covers gray literature, thesis datasets, international repositories; no paywall.

**Dryad Digital Repository** (datadryad.org)
- URL: `https://datadryad.org/search`
- **Search terms for trait data:**
  - `"plant" AND ("trait" OR "functional" OR "morphology" OR "physiology" OR "hydraulic" OR "metabolic")`
  - `"wood density" OR "SLA" OR "LDMC" OR "leaf nitrogen" OR "root" OR "seed mass"`
- **Search terms for occurrence data:**
  - `"occurrence" OR "herbarium" OR "specimen" OR "flora" OR "checklist" AND "plant" AND (darwin OR dwc OR coordinates)`
- **API endpoint:** `https://datadryad.org/api/v2/datasets?query={q}&sort=dateModified-DESC`
- **Facets:** license (CC0, CC-BY), publication status (published), size >1MB (likely >100 rows)
- **Advantage:** DOI-guaranteed, machine-readable metadata, strong peer-review linkage.

**GBIF (Global Biodiversity Information Facility)**
- URL: `https://www.gbif.org/dataset/search`
- **Discovery method 1: Search published datasets**
  - `https://www.gbif.org/dataset/search?q={query}&publishingCountry=&licence=CC_BY_4_0&publishingOrg={?}`
  - Restrict to datasets with `>1000 records`, `last_indexed_date: last 2 years`
- **Discovery method 2: IPT (Integrated Publishing Toolkit) network**
  - List of national/institutional IPTs: `https://www.gbif.org/ipt`
  - Each IPT hosts standardized DwC archives; search within regions of interest (Africa, Central Asia, South America, Oceania)
  - Example: `https://ipt.gbif.org/` → filter by geographic region
- **API endpoint (dataset discovery):** `https://www.gbif.org/api/dataset/search?query={q}&limit=100&offset={n}`
- **API endpoint (species occurrences):** Query by dataset UUID if promising
- **Advantage:** Standardized Darwin Core format; global coverage with strong institutional backing.

**GBIF Registry** (discovery within GBIF-affiliated sources)
- URL: `https://www.gbif.org/organization/search`
- Enumerate regional/national nodes (e.g., Africa Node, Asia-Pacific Node) and their published dataset portfolios
- **Regional focus query:** Filter by organization geography to identify published occurrence or trait datasets from understudied regions

**Google Dataset Search** (meta-search via indexed schema.org metadata)
- URL: `https://datasetsearch.research.google.com/`
- **Query patterns:**
  - `"plant trait" dataset 2023-2026 filetype:csv`
  - `"herbarium" "specimen" occurrence dataset`
  - `"flora" endemic checklist dataset`
- **Advantage:** Captures datasets with schema.org metadata that aren't in Zenodo/Dryad; includes institutional repositories.
- **Limitation:** Requires manual inspection of results; no API.

---

### Disciplinary & Journal-Specific Repositories

**Biodiversity Data Journal (Pensoft)**
- URL: `https://bdj.pensoft.net/browse`
- **Search:** Filter by article type `Data Paper` + keyword (e.g., "plant", "occurrence", "trait", "flora", "herbarium")
- **Supplementary asset download:** Look for linked GBIF DOI or Zenodo deposit; datasets often vouchered with DOI
- **API/crawl:** Pensoft XML API returns metadata + supplementary file links
  - Example: `https://bdj.pensoft.net/api/v3/articles?keyword=flora&article_type=Data%20Paper`
- **Advantage:** Peer-reviewed data papers with standardized metadata; high scientific credibility.

**PhytoKeys, Diversity & Distributions, Botanical Journal of the Linnean Society** (via Pensoft or Wiley)
- **Search via CrossRef/Unpaywall:**
  - Query: `publisher:"Pensoft" OR publisher:"Wiley" AND (title:("plant trait" OR "occurrence" OR "checklist" OR "herbarium") AND (supplementary OR data))`
  - CrossRef API: `https://api.crossref.org/works?query={q}&rows=100`
  - Filter by `type: dataset` or supplementary availability
- **Supplementary file identification:** Parse XML to extract linked data repositories (Figshare, GBIF, Dryad, Zenodo)

**Scientific Data (Nature Publishing Group)**
- URL: `https://www.nature.com/sdata/`
- **Search:** Browse published data descriptors for plant trait/occurrence studies
- **Filter:** Subject area (Ecology, Evolution, Taxonomy); keyword filters
- **Access:** All papers open-access; datasets typically hosted on Zenodo or Figshare with DOI
- **API search:** CrossRef for papers matching the pattern, then locate linked data DOI in metadata

**Data in Brief (Elsevier)**
- URL: `https://www.journals.elsevier.com/data-in-brief`
- **Search:** Similar to Scientific Data; focus on studies with associated supplementary data
- **API:** CrossRef for papers, then extract data DOI from reference list

**Journal Supplementary Data (broad survey)**
- **Approach:** Query journal websites or CrossRef for papers matching:
  - Title keywords: `"plant trait measurement" OR "herbarium" OR "occurrence data" OR "species distribution" OR "checklist"`
  - Supplement availability (filter for papers with supplementary data)
  - Open access only
- **Tools:** CrossRef API (`https://api.crossref.org/`), Unpaywall API (`https://api.unpaywall.org/`)

---

### Regional Databases & Flora Portals

**Africa & Sub-Saharan Africa**
- **POWO (Plants of the World Online, Kew):** `https://powo.science.kew.org/`
  - Taxonomic backbone; identify species lists by region, then search for occurrence datasets
- **GBIF Africa node:** `https://www.gbif.org/node/6`
  - Query by region (West Africa, East Africa, Southern Africa)
  - Examples: Herbaria of Kenya, Tanzania, Uganda, Nigeria, South Africa
- **SANBI (South African National Biodiversity Institute):** `https://www.sanbi.org/`
  - Query data portal for South African occurrence/plot data
- **RAINBIO:** `https://www.rainbio.org/` (tropical Africa & Madagascar species database)
  - Query for georeferenced species lists
- **Herbier National du Cameroun, Yaoundé:** Check GBIF for Cameroonian herbarium data via national IPT
- **Regional checklist searches:** BioRxiv/AfricaPortal for unpublished/preprint checklists for North Africa (Morocco, Algeria, Tunisia, Egypt)

**Central Asia & Mongolia**
- **Virtual Herbarium projects (Kazakhstan, Kyrgyzstan, Mongolia):**
  - Query Pensoft (BDJ) for herbarium data papers; many published via BDJ with GBIF links
  - Example: Vaganov et al. (Altai Virtual Herbarium already in your registry)
- **iNaturalist (Mongolia, Kazakhstan):** Query via iNaturalist research-grade observations API
  - `https://api.inaturalist.org/v1/observations?place_id={place_id}&quality_grade=research&verifiable=true`
  - Place IDs: Mongolia (6870), Kazakhstan (7418)
- **Floras of Central Asia (checklist compilations):**
  - Search for Turczaninowia (Russian journal of plant systematics); often includes species lists with distributions
  - Query: `"Flora of" AND ("Kazakhstan" OR "Kyrgyzstan" OR "Tajikistan" OR "Mongolia" OR "Central Asia")`

**Asia-Pacific (especially underrepresented: Philippines, Indonesia interior, Papua New Guinea, Australia interior)**
- **GBIF Asia-Pacific node:** `https://www.gbif.org/node/16`
- **ASEAN Centre for Biodiversity:** Enumerate datasets via regional IPTs (Thailand, Vietnam, Cambodia, Laos, Indonesia, Philippines, Malaysia, Myanmar, Brunei)
- **Australian Herbaria & PlantNET (NSW):** `https://www.gbif.org/dataset/` (search for Australian herbaria)
- **PNG Herbarium & Pacific Plant Database:**
  - PNG: Check herbarium data on GBIF for Papua New Guinea
  - Pacific: Query `PacIFlora` (already in your registry) + broader Pacific occurrence datasets
- **iNaturalist (Philippines, Indonesia):** Query research-grade observations by region/country
- **Regional checklists:** BioRxiv/ResearchGate for unpublished Philippine, Indonesian, PNG floras

**Tropical South America (Amazon focus, but also Andes, Atlantic Forest, Cerrado gaps)**
- **GBIF South America node:** `https://www.gbif.org/node/33`
- **ATDN (Amazon Tree Diversity Network):** `https://sites.google.com/naturalis.nl/amazon-tree-diversity-network/`
  - Already in your registry; check for newer compiled datasets
- **RAINFOR (tropical forest plot network):** `https://rainfor.org/`
  - Query for plot-level tree occurrence data
- **DryFlor (Seasonally Dry Tropical Forest):** `http://www.dryflor.info/`
  - Already in your registry; check for expansion datasets
- **Brazil's HERBÁRIO VIRTUAL:** Query via GBIF for Brazilian herbarium specimens
- **Colombian Bioregions (Bystriakova et al.):** Already in registry; check for follow-up datasets

**Mediterranean & North Africa**
- **GBIF Mediterranean:** Regional query via GBIF dataset search
- **Herbarium Online (France, Spain, Italy, Greece, Turkey):** Query national herbaria via GBIF
- **FLORA Med (Mediterranean checklist): `https://www.floramediterranea.org/`
  - Check for downloadable species lists with georeferenced localities
- **North African Flora projects:** Query Pensoft/BioRxiv for Morocco, Algeria, Tunisia, Egypt botanical publications

---

### Trait-Specific Data Repositories & Journals

**TRY Global Plant Trait Database** (Kattge et al., Max Planck Institute)
- URL: `https://www.try-db.org/`
- **Status:** Large centralized trait database; does NOT provide bulk open download, but researchers can submit new trait compilations
- **Action:** Check if specific trait studies related to underrepresented types (metabolic, hydraulic) are being submitted; coordinate with TRY curators
- **Alternative:** Search literature for recent TRY data papers or linked trait datasets on Zenodo/Dryad

**AusTraits** (Falster et al., Australia)
- URL: `https://austraits.org/`
- **Data download:** Open-access trait compilation; already partially in DryadPlantTraits (1.8M rows)
- **Action:** Check for version updates or new trait types added since last harvest

**LEDA (Life-history traits of the Northwest-European flora):** `https://www.leda-traits.org/`
- **Focus:** European plant life-history traits (seed mass, height, leaf area, phenology)
- **Data availability:** Download full database (CSV)
- **Geographic gap:** Strongly temperate Europe; low coverage of tropics/Mediterranean

**FRED (Fine Root Ecology Database):** `https://roots.ornl.gov/`
- **URL:** `https://roots.ornl.gov/`
- **Data:** Already partially in DryadPlantTraits (16.9k rows); majority of archives inaccessible (noted as 635/681 files unavailable)
- **Action:** Contact FRED team for bulk data access OR identify newly accessible datasets; prioritize hydraulic root traits

**TraitHub (tundra):** Already in DryadPlantTraits (92k rows)
- **Check:** For dataset updates and new trait types added to the repository

**Ecocrop (crop trait database, FAO):** `http://www.ecocrop.fao.org/`
- **Focus:** Cultivated plant traits; may have limited use for wild species but useful for crop-wild relatives
- **Data access:** Check for downloadable trait tables

**Journal of Ecology, Functional Ecology, New Phytologist (trait-focused papers):**
- **Search strategy:** Query journal archives for papers with supplementary trait tables matching underrepresented trait types
- **API:** CrossRef for papers with `keyword: ("metabolic trait" OR "hydraulic" OR "reproduction" OR "root architecture")`

---

### Biodiversity & Specimen Databases (Occurrence focus)

**Integrated Digitized Biocollections (iDigBio):** `https://www.idigbio.org/`
- **Coverage:** Primarily North American museum specimens, but increasingly global
- **Query:** `https://www.idigbio.org/search` → filter by plant, vascular, geographic region
- **API endpoint:** `https://api.idigbio.org/`
- **Advantage:** Specimen-based with high coordinate quality; linked to museum provenance
- **Limitation:** Weighted toward North America; limited tropical coverage

**Herbaria Catalogue (Index Herbariorum):** `https://sweetgum.nybg.org/science/ih/`
- **Use:** Identify herbaria with online specimen databases; search their individual portals for occurrences
- **Example:** Herbarium of Kew (already digitized & on GBIF), NHM London, Field Museum Chicago

**iNaturalist:** `https://www.inaturalist.org/`
- **API:** `https://api.inaturalist.org/v1/observations`
- **Research-grade query:** Filter by quality_grade=research, taxon taxonomy (Plantae, vascular), geographic region
- **Output:** Research-grade observations (QA-filtered by community); often geovalid with >3m precision
- **Caveat:** Citizen-science bias toward accessible regions; underrepresents remote tropics
- **Use case:** Supplementary occurrence data for common species; NOT sufficient as primary occurrence source alone

**OBSERVATION.org (European & broader network):** `https://observation.org/`
- **Similar to iNaturalist:** Citizen-science platform; API available
- **Geographic focus:** Europe + expanding

**EOL (Encyclopedia of Life) Collections:** `https://collections.eol.org/`
- **Query:** Linked specimen data from museums and herbaria
- **API:** `https://eol.org/api/` (limited; primarily for metadata)

---

### Preprints & Gray Literature

**BioRxiv** (Cold Spring Harbor preprint server)
- URL: `https://www.biorxiv.org/`
- **Search:** Query for preprints with data deposits (Zenodo, Figshare, OSF)
  - Keywords: `"plant trait" OR "occurrence" OR "herbarium" OR "flora"`
  - Filter by subject: Ecology, Evolutionary Biology
  - Date range: Last 18 months (captures work nearing publication)
- **API:** `https://api.biorxiv.org/` (basic search)
- **Action:** Identify promising preprints; check for associated data DOI before paper is published

**PubPeer & ResearchGate preprints:**
- **Search:** `ResearchGate.net/publication/` for datasets attached to papers or profiles
- **Limitation:** Requires manual inspection; high noise-to-signal ratio

**Figshare:** `https://figshare.com/`
- **Search:** Query `figshare.com/search` for datasets
  - Keywords matching above patterns
  - Filter: `filetype: csv, xlsx` (likely tabular data)
  - Sort by `most recent` or `most views`
- **API endpoint:** `https://api.figshare.com/v2/articles?search_for={query}`
- **Advantage:** Accepts datasets from researchers worldwide; includes DOI
- **Caveat:** No peer-review gate; quality variable

**OSF (Open Science Framework):** `https://osf.io/`
- **Search:** Similar to Figshare; lower barrier to entry, so higher noise
- **API:** Available but limited

---

## 2. Initial Filtering Heuristic

Apply these 5 gates sequentially to triage hundreds of candidates down to <20 high-confidence prospects per quarter.

### Gate 1: Publication Status & Curation

**Criterion:** Is the source peer-reviewed, expert-curated, or published in an open-access data journal?

**Decision rule — ACCEPT if ANY of:**
- ✓ Data paper in peer-reviewed journal (Pensoft BDJ/PhytoKeys, Scientific Data, Ecology Letters Data Papers, Data in Brief)
- ✓ Associated with published peer-reviewed research paper (supplementary data with DOI)
- ✓ Curated by established institution with governance (GBIF node, national herbarium, long-standing database like TRY)
- ✓ Dataset has editorial/scientific review statement in metadata (e.g., "expert-validated", "voucher-checked", "scientific review completed")

**Decision rule — REJECT if ANY of:**
- ✗ Purely crowdsourced with no curation (exception: iNaturalist research-grade only)
- ✗ No publication or curation governance evident
- ✗ Gray-literature report with no DOI or persistent identifier
- ✗ Abandoned project (last update >5 years ago with no maintenance stated)

**Flag for manual review:**
- ⚠ Institutional repository without DOI (contact institution to obtain DOI or persistent URL)
- ⚠ Preprint not yet published (defer until paper is accepted; capture the data DOI)

---

### Gate 2: Data Schema Compatibility

**Criterion:** Can the data be parsed into Darwin Core (occurrence) or trait-harmonizable schema (traits)?

**For occurrence data — ACCEPT if ANY of:**
- ✓ Already in Darwin Core format (XML DwC-A or CSV with DwC column headers: `occurrenceID`, `decimalLatitude`, `decimalLongitude`, `scientificName`, etc.)
- ✓ Contains columns that map to DwC core: taxon name (binomial), latitude, longitude, date (event date), collection info
- ✓ Herbarium specimen data with taxon, collection locality (text or coordinates), museum catalog number

**For occurrence data — REJECT if:**
- ✗ Presence-only checklist with no coordinates (unless combined with other sources)
- ✗ Spatial data only (coarse grid cells, administrative units) without species-level linkage
- ✗ No taxonomic identification column or all entries are "Unknown", "sp.", "cf."
- ✗ Coordinates but no taxon information

**For trait data — ACCEPT if ANY of:**
- ✓ Trait columns labeled with standard names (e.g., "specific leaf area", "wood density", "seed mass") OR can be cross-walked via trait synonym vocabulary
- ✓ Includes units (e.g., "g/cm³", "cm²/g", "mg") in separate column or within value (e.g., "2.3 g/cm³")
- ✓ Trait names with species/accession identifiers allowing taxon-level rollup
- ✓ Measurement protocol documented (even if in paper, not data file) — captures replication level, instrument, date

**For trait data — REJECT if:**
- ✗ No units or units cannot be inferred
- ✗ Traits are undocumented abbreviations or free-form text with >3 variants per trait (e.g., "sla", "SLA", "specific leaf area" all present, no normalization)
- ✗ Mixed measurement types in same trait column (e.g., some rows in mg, others in g, no unit column)
- ✗ No taxon linkage or taxon column contains mostly "Unknown"

**Flag for manual review:**
- ⚠ Novel trait type not in existing DryadPlantTraits dictionary — assign to subject-matter expert for unit & protocol validation

---

### Gate 3: Size & Data Completeness

**Criterion:** Dataset is large enough to be useful and complete enough to avoid excessive QA losses.

**For occurrence data — ACCEPT if:**
- ✓ ≥100 unique occurrence records (georeferenced or checklist-based)
- ✓ ≥80% of records have taxon information (name column populated)
- ✓ ≥50% of records have geographic information (coordinates OR locality text that can be georeferenced)

**For occurrence data — REJECT if:**
- ✗ <100 records total
- ✗ >50% missing taxon names
- ✗ >80% missing geographic information

**For trait data — ACCEPT if:**
- ✓ ≥100 trait observations (rows)
- ✓ ≥80% of rows have taxon ID + trait name + trait value
- ✓ ≥70% of rows have units (explicit or inferable)

**For trait data — REJECT if:**
- ✗ <100 observations
- ✗ >40% of rows have missing critical fields (taxon, trait name, or value)

**Flag for manual review:**
- ⚠ Dataset is 100–200 rows but covers rare underrepresented region/trait type (escalate to scientist)
- ⚠ Dataset has high missingness but is from critical geographic gap (evaluate importance vs. QA cost)

---

### Gate 4: License & Open Access

**Criterion:** Data are openly licensed and freely downloadable without registration barriers (or registration is free).

**ACCEPT if ANY of:**
- ✓ CC0 (Public Domain Dedication)
- ✓ CC-BY (Attribution) or CC-BY-SA (Attribution-ShareAlike)
- ✓ ODC-BY (Open Data Commons Attribution)
- ✓ CC-BY-NC (Attribution-NonCommercial) — acceptable for research use; note restriction in provenance
- ✓ Data available from government repository (inherently public)
- ✓ Data available via DOI (Zenodo, Dryad, Figshare DOIs are open-access by policy)

**REJECT if:**
- ✗ CC-BY-ND (no derivatives) — precludes integration/harmonization
- ✗ CC-BY-NC-ND (most restrictive) — precludes research use for commercial downstream
- ✗ Proprietary / restricted license requiring explicit permission
- ✗ Access requires paid subscription or paywalled journal (unless supplementary data separately open)
- ✗ Data access requires signing data-use agreement with unexplained restrictions

**Flag for manual review:**
- ⚠ Data under CC-BY-NC (non-commercial) — document restriction; may still ingest for research use
- ⚠ Data with use restrictions but DOI/citable (contact author for clarification before ingestion)

---

### Gate 5: Explicit Taxon & Geographic Coverage Declaration

**Criterion:** Dataset metadata or paper clearly states geographic scope and taxonomic scope (avoids silent subsetting or undocumented exclusions).

**ACCEPT if ANY of:**
- ✓ Paper/metadata explicitly states "geographic scope: [region]" and "taxonomic scope: [plant group/rank]"
- ✓ Metadata includes explicit inclusion/exclusion criteria (e.g., "only native plants", "trees >10cm DBH", "vascular plants only")
- ✓ Title or abstract clearly conveys scope (e.g., "Checklist of vascular plants of Myanmar", "Tree-level occurrences in Amazon plots")
- ✓ Data dictionary or supplementary documentation describes column meanings + any filtering applied

**REJECT if:**
- ✗ No metadata or paper describing scope
- ✗ Scope is ambiguous (e.g., "plant data" with no geographic or taxonomic qualifier)
- ✗ Evidence of hidden subsetting (e.g., paper says "we compiled 10,000 records" but dataset has 2,000 with no explanation)
- ✗ Apparent filtering criteria not documented (e.g., all coordinates in dataset are >100m precision but metadata says nothing about filtering)

**Flag for manual review:**
- ⚠ Scope is stated but contradicts dataset composition (e.g., "should be 5000 records" but only 1200 present; document discrepancy)
- ⚠ Filtering applied post-publication (e.g., coordinate validation removed records; note this in provenance)

---

## 3. Citation & Provenance Checkpoint

Before ingesting any source, confirm that **all of the following required metadata fields are present or obtainable**:

### Required Metadata Fields

| Field | Source | Requirement | Example |
|---|---|---|---|
| **DOI** | Dataset or paper | Stable, resolvable persistent identifier | `10.5061/dryad.x3ffbg7wt` or `10.3897/BDJ.9.e75590` |
| **Title** | Dataset or paper | Clear, descriptive | "Checklist of endemic vascular plants of the Lesser Sunda Islands" |
| **Author/Curator** | Dataset or paper metadata | Full name(s) and institutional affiliation | "Jennings et al. (2026), University of Arizona" |
| **Publication date** OR **Data release date** | Metadata | ISO 8601 format (YYYY-MM-DD) | `2026-04-29` |
| **License** | Dataset metadata field | Explicit CC license or open-data declaration | `CC-BY-4.0` |
| **Last updated** | Metadata or repository log | Date of most recent modification | `2026-04-29` |
| **Dataset size** | Metadata | Row count or record count (or stated in paper) | "176,150 occurrence records" |
| **Taxonomic scope** | Paper abstract or data dictionary | Explicit statement of included plant groups | "Vascular plants only" or "Eudicots" |
| **Geographic scope** | Paper abstract or metadata | Region(s) covered | "Lesser Sunda Islands, Indonesia" |
| **Data format** | File listing or metadata | CSV, XLSX, JSON, DwC-A, etc. | `CSV` |
| **Column definitions** | Data dictionary or paper supplement | Meaning of each column | See data dictionary link |

### Critical Flags (Check Before Ingestion)

| Flag | Action |
|---|---|
| **No DOI** | Attempt to register with DataCite or request from repository; if not possible, assign strong caveat to ingestion (non-citable source). |
| **Unclear curation or abandoned project** | Contact data provider or last author; request clarification on maintenance status. If no response in 2 weeks, mark for deferred review. |
| **Non-transparent license or use terms** | Contact authors/publisher; request explicit CC-BY or CC0 declaration before ingestion. |
| **Coordinate precision undocumented** | Flag in provenance; note that precision is unknown; may limit use in downstream spatial analyses. |
| **Trait units inferred (not stated)** | Assign QA flag; mark for unit confidence scoring during compilation (see DryadPlantTraits QA pipeline). |
| **Data version not specified** | Document access date + URL; request version/release date from provider if ambiguous. |
| **Taxon identification method not stated** | Flag for manual review; if identifications are not vouchered or verified, note in provenance. |

---

## 4. Geographic & Taxonomic Gap Mapping

### Current Coverage (as of 2026-04-29)

#### Occurrence data (165k compiled rows + 176k literature records; 46 sources + 11 papers)
| Region | Coverage | Priority for new sources |
|---|---|---|
| Southeast Asia | Strong (Sunda-Sahul, Myanmar, Sumatra, Lesser Sunda, Philippines) | **Low** — well-covered by current registries |
| South America | Good (Amazon tree plots, ATDN, DryFlor, Chile, Argentina plots) | **Medium** — gaps remain in interior Amazon, Cerrado, Atlantic Forest understory |
| Russia & Central Asia | Strong (Kyrgyzstan, Altai, Siberian Arctic, Mongolia) | **Medium** — coverage good for northern zones; southern Central Asia (Tajikistan, Turkmenistan) underrepresented |
| North Africa | **CRITICAL GAP** (0 sources) | **URGENT** — Morocco, Algeria, Tunisia, Egypt, Libya, Sudan — no current coverage |
| Sub-Saharan Africa (except southern) | **CRITICAL GAP** (2 sources: Gabon, Central Africa ECAT) | **URGENT** — West Africa, East Africa interior, Congo Basin — severely underrepresented |
| Tropical Asia interior | **CRITICAL GAP** (limited beyond margins) | **URGENT** — PNG, interior Indonesia, interior Philippines, interior Malaysia — few sources |
| Australia | **CRITICAL GAP** (0 occurrence sources) | **URGENT** — endemic-rich continent with minimal current coverage |
| Mediterranean | **CRITICAL GAP** (0 sources) | **High** — Greece, Italy, Spain, North Africa Mediterranean coast — no current coverage |

#### Trait data (2.3M compiled rows; 5 providers)
| Trait type | Coverage | Priority for new sources |
|---|---|---|
| Leaf traits (SLA, LDMC, leaf area, leaf N/P) | Strong (AusTraits, TRY submissions, Dryad compilations) | **Low** |
| Wood/stem traits (wood density, DBH, height) | Good (AusTraits, forest plots) | **Low** |
| Seed traits (seed mass) | Good (AusTraits, Dryad compilations) | **Low** |
| **Hydraulic traits (p50, p88, xylem vulnerability)** | **CRITICAL GAP** (FRED partial, few other sources) | **URGENT** — essential for drought/water-stress modeling |
| **Metabolic traits (respiration, photosynthesis rate, carbohydrate reserves)** | **CRITICAL GAP** (sparse; mainly lab studies) | **URGENT** — underrepresented in open databases |
| **Root traits (root architecture, specific root length, root tissue density, laterality)** | **Gap** (FRED partial/inaccessible; few others) | **Urgent** — critical for below-ground ecology models |
| **Reproductive traits (allocation to reproductive tissue, fruit/seed production, flowering phenology)** | **Gap** (scattered literature; few compilations) | **High** — especially for species with multiple reproduction modes |
| Foliar nutrient concentrations (N, P, K, etc.) | Moderate (AusTraits, scattered papers) | **Medium** — can improve for tropical species |

### Gap-Filling Decision Matrix

Before proposing a new source, cross-check:

1. **Geographic novelty:** Does it cover a CRITICAL GAP region (list above)?
2. **Taxonomic novelty:** Does it target an underrepresented plant group (e.g., ferns, bryophytes, succulent-rich floras)?
3. **Trait novelty:** Does it measure an underrepresented trait type?
4. **Sample size:** Will it add ≥500 novel records/observations (avoid micro-datasets unless exceptionally high-value)?
5. **Uniqueness:** Cross-check dataset coordinates/taxa against existing 46-source occurrence registry and 5-provider trait registry using fuzzy matching. If >70% overlap detected, flag for deduplication review before ingestion.

**Scoring:** Assign each candidate a gap-fill score:
- **Score 3 (ingest immediately):** Covers 2+ critical gaps (geography + trait type, or geography + remote region)
- **Score 2 (high priority):** Covers 1 critical gap + ≥500 novel records
- **Score 1 (medium priority):** Fills secondary gap (Medium or Low priority region/trait)
- **Score 0 (defer or skip):** Minimal gap-fill potential; high overlap with existing sources

---

## 5. Scientific Validation Criteria

### For Trait Data

Before integrating trait observations into compiled_trait_observations.csv:

#### Unit Declaration & Protocol Documentation

- ✓ **REQUIRED:** Trait units are explicitly stated in dataset OR in associated paper
- ✓ **REQUIRED:** Units conform to SI (International System of Units) or are cross-walkable to SI equivalents
  - Examples: mm, cm, g, kg, mg, m²/s (photosynthesis), MPa (pressure), J/g (energy)
  - Flagged for review: Non-standard abbreviations (e.g., "units?" or "mixed"), ambiguous (e.g., "fresh wt" vs. "dry wt" unclear)
- ✓ **STRONGLY RECOMMENDED:** Measurement protocol is cited or described
  - Examples: "Following Pérez-Harguindeguy et al. (2013) protocol", "measured with PAM fluorometer", "oven-dried at 60°C"
  - Caveat: If protocol is not stated, note in `source_column_protocol` field as `unknown`

#### Replication & Precision Level

- ✓ **DOCUMENTED:** Replication level (sample size per species/individual)
  - Examples: "n=3 replicate measurements per individual", "mean of 5 plants", "single measurement per specimen"
  - If not stated: Flag in QA output; note as `replication_level: unknown`
- ✓ **PRECISION:** Measurement resolution (significant figures) are appropriate to trait type
  - Example flag: Hydraulic p50 values reported to 0.0001 MPa may be falsely precise; if instrumental precision is <0.1 MPa, note caveat

#### Trait Coverage (Completeness within dataset)

- ✓ Missing data handling: Dataset should document how missing/invalid values are encoded
  - Acceptable: `NA`, `null`, `-9999` with explicit documentation
  - Unacceptable: Blank cells with no documentation; ambiguity between "not measured" vs. "not applicable"
- ✓ Outlier documentation: If dataset includes bounds or exclusion criteria (e.g., "values >3 SD from mean excluded"), state this explicitly

#### Taxonomic Context

- ✓ Species identification: Trait values linked to species-level (minimum) or subspecies identifier
  - Caveat: Accept "genus + epithet" even if full authority/date not provided; flag incomplete authorship
- ✓ Specimen voucher (for lab-measured traits): If available, note herbarium catalog number

---

### For Occurrence Data

Before integrating occurrence records into Darwin Core compiled table:

#### Coordinate Precision & Accuracy

- ✓ **REQUIRED:** Coordinate precision (uncertainty) is documented
  - Examples: "accurate to 1 km", "precision: 100m", `coordinateUncertaintyInMeters: 1000`
  - If not stated: Attempt to infer from coordinate format (decimal degrees to 2 places = ~1 km; to 4 places = ~10m) OR mark as `precision: unknown` and flag for spatial analysis caveats
- ✓ **GEOSPATIAL QA:** Coordinates must pass basic validity checks:
  - Latitude within [-90, 90], Longitude within [-180, 180]
  - Not on disputed/ambiguous political boundaries (flag if >1 border crossing in dataset without explanation)
  - Coordinate resolution appropriate to basis of record (e.g., herbarium specimen ≥1m reasonable; citizen science ≥100m common)

#### Basis of Record & Collection Effort Transparency

- ✓ **REQUIRED:** Basis of record is explicitly documented (Darwin Core field `basisOfRecord`)
  - Acceptable categories: HumanObservation, PreservedSpecimen, FossilSpecimen, LivingSpecimen, MaterialSample, Observation, MachineObservation
  - Caveat: "HumanObservation" includes expert field surveys AND citizen science; note if mixed
- ✓ **COLLECTION EFFORT:** Dataset should disclose whether:
  - It is an exhaustive survey (e.g., "all herbarium specimens in collection X") vs. convenience sample
  - Sampling was spatially stratified or random
  - Effort metrics are provided (e.g., "survey of 50 herbaria", "standardized plots, n=20")
  - Record count reflects actual collection effort (not down-sampled or up-sampled post-collection)

#### Taxonomic Validation & Curation

- ✓ **SCIENTIFICALLY CURATED:** Species identifications should be made by expert or vouchered
  - Acceptable: Herbarium specimens (inherently vouchered), expert-verified iNaturalist records, published checklist with cited authorities
  - Caveat: Citizen-science observations without taxonomist review; note in provenance
- ✓ **NAME STANDARDIZATION:** Taxon names follow accepted nomenclature
  - Flag for unit validation: Names that are synonyms, misspellings, or outdated authorities (e.g., species attributed to wrong author)
  - Acceptable: Names follow current IPNI, POWO, or WCVP standards (or state version used)

#### Hidden QA Losses & Filtering Transparency

- ✓ **DISCLOSED:** If records were filtered before publication (e.g., "we excluded records with coordinate uncertainty >10 km", "records with <3 supporting specimens removed"), this MUST be stated in paper/metadata
  - Caveat: If filtering criteria are not disclosed, note in provenance: "filtering criteria unknown"
  - Example red flag: Dataset metadata says "10,000 records compiled" but published dataset has 2,000; if paper doesn't explain why, contact authors
- ✓ **SAMPLING BIAS ACKNOWLEDGED:** Dataset or paper should acknowledge geographic/taxonomic bias
  - Example: "Most records from herbaria in capital cities; remote regions undersampled"
  - Caveat: If bias is not acknowledged, data scientist should note this limitation in downstream analyses

#### Native/Introduced/Cultivated Status

- ✓ **NATIVE STATUS PROVENANCE:** If dataset includes `native_status` or `is_introduced` fields, the **source of this interpretation must be cited**
  - Acceptable: Field-tested presence (e.g., "specimen collected from wild population"), literature source (cite authority), expert determination with affiliation
  - Caveat: Never treat native/introduced as universal truth; always link to geographic context + data source
  - Example: "Native to Australia" is NOT sufficient; should be "Native to eastern Australia (source: Dept. Environment & Science, 2025)" or cite peer-reviewed authority

---

## 6. Recommended Immediate Search Entry Points

### Top 5 Entry Points to Execute Immediately

#### **1. North Africa & Sub-Saharan Africa Gap-Filling Sprint**

**Target:** 3–5 novel occurrence sources covering Morocco, Algeria, Tunisia, Egypt, West Africa, Congo Basin
- **Primary search:** GBIF Africa node datasets + BioRxiv preprints
- **Secondary search:** National herbarium data (Egypt National Museum, Morocco Royal Herbarium, Kew Africa herbaria)
- **Tool:** GBIF API query by region; iDigBio for African herbaria data
- **Expected yield:** 2–3 datasets passing gate filters
- **Timeline:** 1 week
- **Gap score:** 3 (CRITICAL geographic gap; will immediately improve continental coverage)
- **Search queries:**
  - `https://www.gbif.org/api/dataset/search?query=Africa&publishingCountry=EG,MA,DZ,TN,ZA&sort=mostRecent`
  - BioRxiv: `"Flora of" AND ("Africa" OR "Morocco" OR "Algeria" OR "Egypt") AND (2024 OR 2025 OR 2026)`

#### **2. Tropical Asia Interior Targets (Philippines, PNG, Interior Indonesia)**

**Target:** 2–3 occurrence datasets from undersampled interior regions
- **Primary search:** GBIF Philippines, PNG, Indonesia nodes; iNaturalist research-grade by region
- **Secondary search:** Pensoft BDJ for recent biodiversity surveys in these regions
- **Tool:** GBIF IPT enumeration for national datasets; iNaturalist API
- **Expected yield:** 1–2 datasets + 1 iNaturalist research-grade export
- **Timeline:** 1 week
- **Gap score:** 3 (CRITICAL geographic gap; high-biodiversity regions)
- **Search queries:**
  - `https://www.gbif.org/api/dataset/search?query=Philippines&limit=100`
  - Pensoft BDJ: `title:("Papua New Guinea" OR "Philippines" OR "Borneo") AND year:[2023 TO 2026]`
  - iNaturalist: `place_id=6801` (Philippines), filtered by research_grade

#### **3. Hydraulic & Root Trait Compilation Sprint**

**Target:** Identify 4–6 publications with lab-measured hydraulic traits (p50, p88, water potential) and root architecture data; harvest supplementary datasets
- **Primary search:** Cross-Ref API for papers matching trait keywords + supplementary data availability
- **Secondary search:** Zenodo/Figshare for trait datasets labeled "hydraulic" or "root"
- **Tool:** CrossRef API, Zenodo/Figshare programmatic search
- **Expected yield:** 3–4 datasets with documented units and protocols
- **Timeline:** 2 weeks (includes manual curation of trait units)
- **Gap score:** 3 (CRITICAL trait gap; essential for drought/water-stress models)
- **Search queries:**
  - CrossRef: `query=("hydraulic trait" OR "xylem vulnerability" OR "water potential") AND (supplement OR data OR dataset) AND year:[2023 TO 2026]`
  - Zenodo: `("hydraulic" OR "root architecture" OR "xylem") AND (trait OR measurement) AND filetype:csv`

#### **4. Australia Vascular Flora Inventory**

**Target:** 1–2 national/regional occurrence datasets covering Australian endemic and widespread species
- **Primary search:** GBIF Australia node; Plantnet NSW (state herbarium); Australian National Herbarium
- **Secondary search:** ASRIS (Australian Soil and Land Survey); Atlas of Living Australia (ALA)
- **Tool:** GBIF API, ALA API
- **Expected yield:** 1–2 datasets covering multi-state Australian flora
- **Timeline:** 1 week
- **Gap score:** 3 (CRITICAL geographic gap; Australia is mega-endemic but absent from current registry)
- **Search queries:**
  - `https://www.gbif.org/api/dataset/search?publishingCountry=AU&sort=mostRecent&limit=100`
  - ALA API: `https://biocache-ws.ala.org.au/ws/webportal/search?q=*:*&fq=phylum:Charophyta`

#### **5. Mediterranean Flora (Greece, Italy, Spain, coastal North Africa)**

**Target:** 2–3 Mediterranean endemic checklists or herbarium datasets with georeferencing
- **Primary search:** GBIF Mediterranean + national herbarium networks
- **Secondary search:** FLORAMEDITERRANEA.org for linked occurrence datasets; Pensoft for recent Mediterranean floras
- **Tool:** GBIF API, manual crawl of herbarium portals
- **Expected yield:** 1–2 datasets with Mediterranean endemic coverage
- **Timeline:** 1 week
- **Gap score:** 2–3 (High priority geographic + trait gap; Mediterranean climate regions underrepresented)
- **Search queries:**
  - `https://www.gbif.org/api/dataset/search?query=Mediterranean&sort=mostRecent&limit=100`
  - Pensoft BDJ: `title:("Mediterranean" OR "Greece" OR "Italy" OR "Spain") AND (endemic OR flora OR checklist) AND year:[2023 TO 2026]`

---

### Quick-Start Toolkit (Commands & Scripts)

#### **Query GBIF via API (R snippet)**
```r
library(rgbif)
# Search GBIF datasets by region + keywords
gbif_datasets <- dataset_search(query = "vascular flora", limit = 100)
# Filter for open-access, recent datasets
open_access <- gbif_datasets[grepl("CC-BY", gbif_datasets$license), ]
```

#### **Query Zenodo via API (bash)**
```bash
curl -s "https://zenodo.org/api/records?q=plant+trait+dataset&type=dataset&sort=mostrecent&size=100&page=1" \
  | jq '.hits.hits[] | {title: .metadata.title, doi: .metadata.doi, files: .files}'
```

#### **Query Pensoft BDJ via API (bash)**
```bash
curl -s "https://bdj.pensoft.net/api/v3/articles?keyword=flora&article_type=Data%20Paper&limit=100" \
  | jq '.result[] | {title: .title, doi: .doi}'
```

#### **iNaturalist Research-Grade Export (bash + curl)**
```bash
# Export research-grade vascular plant observations for a region (e.g., Philippines place_id=6801)
curl -s "https://api.inaturalist.org/v1/observations?place_id=6801&quality_grade=research&taxon_name=Plantae&order_by=created_at&per_page=10000" \
  | jq '.results[] | {species: .taxon.name, lat: .geom.coordinates[1], lon: .geom.coordinates[0]}' \
  > philippines_inaturalist_research_grade.json
```

---

## Maintenance & Quarterly Update Protocol

### Quarterly Discovery Cycle (recommended frequency)

1. **Week 1–2: Search execution** — Run all search queries listed in Section 1 (search strategy). Document candidates in temporary registry file: `data/candidate_sources_YYYY_QX.csv`
2. **Week 2–3: Gate triage** — Apply Gates 1–5 (Filtering Heuristic) to candidate list. Move high-confidence prospects to `data/sources_ready_for_curation_YYYY_QX.csv`
3. **Week 3–4: Provenance audit** — Run Citation & Provenance Checkpoint on final candidates. Confirm all required metadata. Document blockers (missing DOI, unclear license, etc.)
4. **Week 4: Gap-fill scoring** — Run gap-fill decision matrix (Section 4) on each candidate. Rank by gap-fill score (3 > 2 > 1). Recommend top 5 for ingestion in next quarter.
5. **Documentation:** Append discovery log to `agents/discovery_vetting_strategy.md` with:
   - Date of search
   - Query terms used
   - Number of candidates found, passed gates, final recommendations
   - Notes on any new data platforms discovered or search strategy refinements

### Version Control & Attribution

- Maintain discovery workflow in version control: `agents/discovery_vetting_strategy.md`
- Append quarterly discovery summaries to `agents/agent_chat_provenance_log.txt` with user, date, and outcome
- Link any ingested sources back to this workflow via `source_discovery_date` and `discovery_workflow_version` columns in source registries

---

## Appendix: Common Data Wrangling Issues & Solutions

### Issue: Dataset has good coverage but no DOI
**Solution:** 
1. Check for persistent URL (GitHub repo URL, institutional repository URL)
2. Contact data curator/author to request DataCite DOI registration
3. If no DOI available, manually create citation with access date: "Author et al. (YYYY). Dataset name. Accessed YYYY-MM-DD from [URL]."
4. Proceed with ingestion but flag in provenance: `doi_status: "no_doi_available; access_date: YYYY-MM-DD"`

### Issue: Trait units are non-standard or mixed
**Solution:**
1. Check paper/supplement for unit conversions or protocols
2. Cross-walk against TRY unit glossary or trait measurement handbook (Pérez-Harguindeguy et al. 2013)
3. If ambiguous, flag for expert review; do NOT harmonize without confirmation
4. Assign unit confidence score (1 = certain, 0.5 = inferred, 0 = unknown) in QA output

### Issue: Occurrence data are coordinate-only with no taxon info
**Solution:**
1. Check if coordinates can be linked to associated checklist (e.g., "species survey at this location")
2. If stand-alone coordinates, classify as `basis_of_record: "Observation"` without species ID; mark as `taxon: unknown`
3. This is generally NOT useful for species-level analyses; flag for low priority unless context is exceptional

### Issue: Herbarium dataset has no explicit native/introduced designation
**Solution:**
1. Assume all herbarium specimens are sourced from wild or cultivated collection sites as documented in record
2. Do NOT infer native/introduced status; leave field blank or mark as `native_status: unknown`
3. Document in provenance: "Native status inferred from specimen collection locality; no explicit designation provided by source."

---

**Last updated:** 2026-04-30  
**Maintained by:** Biodiversity-Science-Guard  
**Workflow version:** 1.0
