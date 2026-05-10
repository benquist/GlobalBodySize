# GlobalBodySize — Data Source Inventory

**Project:** GlobalBodySize — programmatic harvest of global animal and plant body mass / body size data  
**Modeled after:** DryadPlantTraits (DryadPlantTraits/ in this workspace)  
**Date produced:** 2026-05-09  
**Author:** GitHub Copilot (Claude Sonnet 4.6) — research synthesis document  
**Provenance:** Produced in response to user prompt; all facts marked UNVERIFIED where confidence is not high.

> **NOTICE:** This is a research discovery document, not a peer-reviewed synthesis. Every DOI, URL, and record count should be independently verified before use in publications or grant proposals. Entries marked **UNVERIFIED** require manual confirmation.

---

## SECTION 1 — Tier 1 Curated Databases

These are databases with explicit curation, stable DOIs, and primary focus on body mass or body size as a trait variable. Listed in order of taxonomic breadth.

---

### 1.01 PanTHERIA

| Field | Value |
|---|---|
| **Taxonomic scope** | Extant and recently extinct placental and marsupial mammals |
| **Body size variables** | Adult body mass (g), head-body length, tail length, hindfoot length |
| **Species coverage** | ~5,416 mammal species |
| **Access method** | Direct download (Ecological Archives); no dedicated R package — commonly loaded via `read.delim()` from the archived text file |
| **Access URL** | https://esapubs.org/archive/ecol/E090/184/ (UNVERIFIED — confirm ESA archive is still serving this URL) |
| **Citation** | Jones KE, et al. 2009. PanTHERIA: a species-level database of life history, ecology, and geography of extant and recently extinct mammals. *Ecology* 90(9):2648. DOI: 10.1890/08-1494.1 |
| **DOI status** | Moderately confident — confirm before citing |
| **Data quality** | Gold standard for mammal body mass; values are species means compiled from literature; some gaps for rare tropical species; dry mass not included |
| **Known limitations** | No intraspecific variation; literature-derived means may reflect sex-biased samples; coverage thinner for small-bodied tropical taxa |

---

### 1.02 EltonTraits 1.0

| Field | Value |
|---|---|
| **Taxonomic scope** | All birds (~9,993 species) and mammals (~5,400 species) |
| **Body size variables** | Adult body mass (g) |
| **Access method** | Direct download from Ecological Archives; no R package — `read.delim()` or `data.table::fread()` |
| **Access URL** | https://esapubs.org/archive/ecol/E095/178/ (UNVERIFIED — confirm URL still active) |
| **Citation** | Wilman H, Belmaker J, Simpson J, de la Rosa C, Rivadeneira MM, Jetz W. 2014. EltonTraits 1.0: Species-level foraging attributes of the world's birds and mammals. *Ecology* 95(7):2027. DOI: 10.1890/13-1917.1 |
| **DOI status** | Moderately confident |
| **Data quality** | Highly cited; body mass based on published references; good global coverage for birds; mammals coverage overlaps heavily with PanTHERIA |
| **Known limitations** | Single point estimate per species; no uncertainty bounds; diet proportions are primary focus, mass is supplementary |

---

### 1.03 AVONET

| Field | Value |
|---|---|
| **Taxonomic scope** | All extant bird species (~10,000+ species across three major taxonomies: BirdLife, eBird/Clements, BirdTree) |
| **Body size variables** | Body mass (g), wing length, tarsus length, bill length/depth/width, tail length, Kipp's distance, hand-wing index |
| **Access method** | R package `avian` (UNVERIFIED — confirm package name and availability on CRAN); also available as supplementary data via journal |
| **Access URL** | https://figshare.com (search AVONET Tobias 2022) (UNVERIFIED — confirm Figshare DOI) |
| **Citation** | Tobias JA, et al. 2022. AVONET: morphological, ecological and geographical data for all birds. *Ecology Letters* 25(3):581–597. DOI: 10.1111/ele.13898 (UNVERIFIED — verify DOI) |
| **DOI status** | UNVERIFIED — confirm journal and DOI |
| **Data quality** | Highest quality morphological dataset for birds; measurements from >90,000 individual specimens; standardized protocols across >200 institutions |
| **Known limitations** | Some species represented by very few specimens; sexual dimorphism may not be fully captured; mass from museum specimens may not reflect live mass |

---

### 1.04 AnAge — Animal Ageing and Longevity Database

| Field | Value |
|---|---|
| **Taxonomic scope** | Vertebrates broadly (mammals, birds, reptiles, amphibians, fish) + some invertebrates |
| **Body size variables** | Adult body mass (g or kg), body length; primarily a longevity database with mass as a covariate |
| **Species coverage** | ~4,000+ vertebrate species (UNVERIFIED — confirm current count) |
| **Access method** | Direct download (tab-delimited flat file); no R API wrapper as of last check |
| **Access URL** | https://genomics.senescence.info/species/dataset.zip (UNVERIFIED — confirm URL format) |
| **Citation** | Tacutu R, et al. 2018 (or most recent update). Human Ageing Genomic Resources: new and updated databases and tools for the biology and genetics of ageing. *Nucleic Acids Research*. DOI: UNVERIFIED |
| **DOI status** | UNVERIFIED — locate most recent AnAge publication DOI |
| **Data quality** | Useful as a cross-check source for mass; body mass values are often secondary to the longevity curation; good for mammals and birds |
| **Known limitations** | Mass coverage uneven across groups; not designed as a body mass database; some entries based on very old literature |

---

### 1.05 AmphiBIO

| Field | Value |
|---|---|
| **Taxonomic scope** | Amphibia: Anura, Caudata, Gymnophiona (~6,776 species) |
| **Body size variables** | Body mass (g), body length (SVL), size at maturity, max size |
| **Access method** | Direct download from Figshare or Scientific Data supplementary; no CRAN R package |
| **Access URL** | https://figshare.com/articles/dataset/AmphiBIO_v1/4644424 (UNVERIFIED — confirm Figshare ID) |
| **Citation** | Oliveira BF, São-Pedro VA, Santos-Barrera G, Penone C, Costa GC. 2017. AmphiBIO, a global database for amphibian ecological traits. *Scientific Data* 4:170123. DOI: 10.1038/sdata.2017.123 (UNVERIFIED — confirm) |
| **DOI status** | UNVERIFIED — confirm DOI |
| **Data quality** | Best-available curated database for amphibian body size; significant gaps in tropics for body mass specifically (SVL more complete); literature-compiled |
| **Known limitations** | Body mass missing for many species; SVL is more complete than mass; geographic bias toward well-studied regions |

---

### 1.06 Reptile Body Size Databases

Multiple overlapping sources exist; no single gold-standard database:

#### 1.06a Meiri Lizard Size Database
| Field | Value |
|---|---|
| **Taxonomic scope** | Lizards (Squamata, suborder Lacertilia) |
| **Body size variables** | SVL, body mass |
| **Citation** | Meiri S. 2010. Length–weight allometries in lizards. *Journal of Zoology* 281(3):218–226. DOI: UNVERIFIED; and related updates |
| **Access** | No R package; published as supplementary files — search Dryad/Figshare by Meiri |
| **Notes** | Meiri group has produced multiple iterations; check for most recent compiled dataset |

#### 1.06b Feldman et al. Squamate Size Database
| Field | Value |
|---|---|
| **Taxonomic scope** | Squamates (lizards + snakes) |
| **Body size variables** | Mass, SVL |
| **Citation** | Feldman A, et al. 2016. Body sizes and diversification rates of lizards, snakes, amphisbaenians and the tuatara. *Global Ecology and Biogeography*. DOI: UNVERIFIED |
| **Access** | Supplementary data via journal or Dryad |
| **Notes** | UNVERIFIED — confirm exact paper, DOI, and data availability |

#### 1.06c GARD (Global Assessment of Reptile Distributions)
| Field | Value |
|---|---|
| **Scope** | Reptile distributions (not body mass); note for spatial join |
| **URL** | http://www.gardinitiative.org (UNVERIFIED) |
| **Notes** | Distribution data only; must join with size databases separately |

---

### 1.07 FishBase / rfishbase

| Field | Value |
|---|---|
| **Taxonomic scope** | Fishes (>33,000 species including ray-finned, sharks, rays, jawless) |
| **Body size variables** | Length-weight relationships (W = aL^b parameters a, b); maximum total length; standard length; body mass calculated from LW relationships |
| **Access method** | R package `rfishbase` — available on CRAN; also `fishbase` web portal |
| **R package** | `rfishbase` (Boettiger C, et al.) — install with `install.packages("rfishbase")` |
| **Key functions** | `length_weight()`, `species()`, `estimate()` |
| **Citation** | Froese R, Pauly D (Eds). FishBase. World Wide Web electronic publication. www.fishbase.org. (cite year accessed); rfishbase: Boettiger C, et al. DOI: UNVERIFIED for package citation |
| **Data quality** | Comprehensive for fish; length-weight parameters vary in quality (sample sizes range from 1 to thousands); must propagate LW uncertainty |
| **Known limitations** | Mass is derived (not directly measured) for most species; LW parameters are often from regional populations and may not represent global mean |

---

### 1.08 SeaLifeBase / rsealifebase

| Field | Value |
|---|---|
| **Taxonomic scope** | Marine non-fish organisms (invertebrates, marine mammals, seabirds, reptiles) |
| **Body size variables** | Similar to FishBase: LW parameters, body size |
| **Access method** | R package `rsealifebase` (UNVERIFIED — confirm package name and CRAN status); companion to rfishbase |
| **URL** | https://www.sealifebase.ca (UNVERIFIED — confirm canonical URL) |
| **Notes** | Less developed than FishBase; variable data quality |

---

### 1.09 Open Traits Network

| Field | Value |
|---|---|
| **Taxonomic scope** | Cross-taxonomic; aggregation network |
| **Body size variables** | Variable — aggregates many trait databases including body mass |
| **Access method** | No single unified API; network provides standards and links to member databases |
| **URL** | https://opentraits.org (UNVERIFIED — confirm) |
| **Citation** | Gallagher RV, et al. 2020. Open Science principles for accelerating trait-based science across the Tree of Life. *Nature Ecology & Evolution* 4:294–303. DOI: UNVERIFIED |
| **Data quality** | Meta-network; quality varies by contributing database |
| **Notes** | Good for discovering new datasets; not a queryable API for mass retrieval |

---

### 1.10 EOL TraitBank

| Field | Value |
|---|---|
| **Taxonomic scope** | Cross-taxonomic (all life) |
| **Body size variables** | Body mass, body length, and many other traits scraped from multiple sources |
| **Access method** | REST API; no dedicated R package as of last check |
| **API URL** | https://eol.org/api (UNVERIFIED — confirm current API version and endpoints) |
| **Citation** | Parr CS, et al. 2014. The Encyclopedia of Life v2: Providing Global Access to Knowledge About Life on Earth. *Biodiversity Data Journal* 2:e1079. DOI: UNVERIFIED |
| **Data quality** | Highly heterogeneous; aggregates from many sources without harmonization; treat as discovery tool rather than authoritative source |
| **Known limitations** | Data quality varies enormously; mass values may conflict across source databases; no single unit standard |

---

### 1.11 TRY Plant Trait Database

| Field | Value |
|---|---|
| **Taxonomic scope** | Vascular plants (~280,000+ species partially covered) |
| **Body size variables** | Plant height, stem mass, leaf mass, leaf area, seed mass, seed size, above-ground biomass, root mass |
| **Access method** | Registered download via https://www.try-db.org — requires free account and data request; R helper scripts available informally |
| **Citation** | Kattge J, et al. 2020. TRY plant trait database — enhanced coverage and open access. *Global Change Biology* 26(1):119–188. DOI: 10.1111/gcb.14904 (UNVERIFIED — confirm DOI) |
| **DOI status** | Fairly confident — confirm before citing |
| **Data quality** | Best available for plant traits globally; >12 million trait records from >2,000 contributors; includes intraspecific variation |
| **Known limitations** | Registration required; some data embargoed by contributors; body mass not as cleanly defined for plants as for animals — use plant height and seed mass as primary size proxies |

---

### 1.12 GBIF MeasurementOrFact (Darwin Core Extension)

| Field | Value |
|---|---|
| **Taxonomic scope** | All life — but body mass coverage extremely patchy |
| **Body size variables** | Body mass, body length, and other measurement types (when publishers include this extension) |
| **Access method** | `rgbif` R package — `occ_download()` with Darwin Core extension; also GBIF data portal with `measurementorfact` filter |
| **Citation** | GBIF.org. Accessed [date]. GBIF Occurrence Download. DOI: assigned per download |
| **Data quality** | Highly variable; most occurrence records do NOT include mass measurements; MeasurementOrFact is underused by data publishers |
| **Coverage assessment** | See Section 4 of this document for detailed assessment |

---

### 1.13 VertNet

| Field | Value |
|---|---|
| **Taxonomic scope** | Vertebrates — primarily museum collection specimens (mammals, birds, fish, reptiles, amphibians) |
| **Body size variables** | Body mass when recorded on specimen tags; body length; fat score; reproductive condition |
| **Access method** | R package `rvertnet` (on CRAN); also web portal |
| **R package** | `rvertnet` — `searchbyterm(class = "Mammalia", term = "weight")` |
| **URL** | http://vertnet.org |
| **Citation** | Barve V, Chagnoux S, et al. rvertnet. R package. (UNVERIFIED — confirm canonical citation) |
| **Data quality** | Inconsistent — body mass recorded at time of specimen collection; preserved specimens may differ from live mass; data completeness varies by institution |
| **Notes** | Excellent for accessing raw specimen-level data; requires downstream mass/weight field parsing |

---

### 1.14 IUCN Red List

| Field | Value |
|---|---|
| **Taxonomic scope** | Assessed species across all taxa (~140,000+ species) |
| **Body size variables** | Some species assessments include body mass in narrative text; not structured database fields |
| **Access method** | R package `rredlist` (on CRAN); REST API with token |
| **R package** | `rredlist` — `rl_species()`, `rl_narrative()` |
| **API** | https://apiv3.iucnredlist.org (UNVERIFIED — confirm current API version) |
| **Citation** | IUCN. The IUCN Red List of Threatened Species. Version [year]. https://www.iucnredlist.org |
| **Data quality** | Body mass rarely in structured fields; would require text mining of narrative assessments; not recommended as primary mass source |
| **Notes** | Valuable for taxonomic harmonization and conservation status linkage |

---

### 1.15 Ernest 2003 — Mammal Life History Database

| Field | Value |
|---|---|
| **Taxonomic scope** | Placental non-volant mammals (~1,500 species) |
| **Body size variables** | Adult body mass (g), neonate mass, weaning mass |
| **Access method** | Ecological Archives direct download; commonly bundled in ecology teaching packages |
| **Citation** | Ernest SMK. 2003. Life history characteristics of placental nonvolant mammals. *Ecology* 84(12):3402. DOI: 10.1890/02-9002 (UNVERIFIED — confirm DOI) |
| **Data quality** | Well-used baseline dataset; smaller species coverage than PanTHERIA; includes life history context |
| **Notes** | Useful for allometric analyses; has been superseded in coverage by PanTHERIA but frequently cited |

---

### 1.16 MammalDIET / MammalDIET 2.0

| Field | Value |
|---|---|
| **Taxonomic scope** | Mammals — diet and body mass |
| **Body size variables** | Adult body mass (g) as predictor in diet-mass models |
| **Citation** | Kissling WD, et al. 2014. Establishing macroecological trait datasets: digitalization, extrapolation, and validation of diet preferences in terrestrial mammals worldwide. *Ecology and Evolution*. DOI: UNVERIFIED |
| **Access** | Figshare or Dryad — search "MammalDIET" |
| **Notes** | Body mass included as ecological attribute alongside diet data |

---

### 1.17 BirdFuncDat (Sekercioglu 2012)

| Field | Value |
|---|---|
| **Taxonomic scope** | Birds (~9,900 species) |
| **Body size variables** | Body mass (g) |
| **Citation** | Sekercioglu CH. 2012. Promoting community-wide bird ecology training. *PLoS Biology*. DOI: UNVERIFIED — this citation may be incorrect; verify the primary BirdFuncDat paper |
| **Notes** | Precursor to AVONET; largely superseded by AVONET but still widely used; UNVERIFIED on exact publication |

---

### 1.18 ATLANTIC Series Databases (Neotropical Focus)

| Field | Value |
|---|---|
| **Taxonomic scope** | Various vertebrate groups in the Neotropics |
| **Body size variables** | Body mass, body length in some datasets |
| **Access** | Published as data papers in *Ecology* journal; search Dryad for "ATLANTIC" |
| **Key papers** | ATLANTIC MAMMALS (mammals), ATLANTIC BIRDS, ATLANTIC AMPHIBIANS — search Ecology data papers |
| **Notes** | Neotropical bias; good for South American coverage gap-filling |

---

### 1.19 COMPADRE / COMADRE Population Matrix Databases

| Field | Value |
|---|---|
| **Taxonomic scope** | Plants (COMPADRE) and animals (COMADRE) |
| **Body size variables** | Occasional: stage-based size classes; not primary body mass data |
| **Access method** | R package `Rcompadre` (UNVERIFIED — confirm package name) |
| **URL** | https://compadre-db.org |
| **Notes** | Demographic data primarily; limited use for body mass harvest but may contain stage-structured size information |

---

### 1.20 PREDICTS Database

| Field | Value |
|---|---|
| **Taxonomic scope** | Cross-taxonomic land biodiversity |
| **Body size variables** | Body mass sometimes included as a species attribute in assemblage data |
| **Citation** | Hudson LN, et al. 2017. The database of the PREDICTS project. *Ecology and Evolution*. DOI: UNVERIFIED |
| **Access** | NHM Data Portal — https://data.nhm.ac.uk (UNVERIFIED) |
| **Notes** | Primarily a land-use vs. biodiversity database; body mass is an attribute of taxa, not the primary variable |

---

### 1.21 BioTIME

| Field | Value |
|---|---|
| **Taxonomic scope** | Cross-taxonomic time series assemblages |
| **Body size variables** | Body mass not directly measured; species identities can be joined to body mass databases |
| **Citation** | Dornelas M, et al. 2018. BioTIME: A database of biodiversity time series for the Anthropocene. *Global Ecology and Biogeography*. DOI: UNVERIFIED |
| **Access** | http://biotime.st-andrews.ac.uk (UNVERIFIED) |
| **Notes** | Use as taxonomic lookup to join body mass from other sources; not a body mass database itself |

---

### 1.22 Arthropod Body Size Databases

Multiple fragmented sources; no unified global database:

#### 1.22a Ant Trait Database
| Field | Value |
|---|---|
| **Scope** | Ants (Formicidae) |
| **Body size variables** | Worker body mass, body length, head width |
| **Citation** | Ant Trait Database — Parr CL, et al. (UNVERIFIED — confirm authorship and DOI) |
| **Access** | Search Dryad/Zenodo for "ant trait body mass" |

#### 1.22b Body Size of Freshwater Macroinvertebrates (Usseglio-Polatera et al.)
| Field | Value |
|---|---|
| **Scope** | European freshwater macroinvertebrates |
| **Notes** | European database; UNVERIFIED on formal citation; search for "freshwater invertebrate body mass" on Dryad |

#### 1.22c Insect Body Size Compilations (various)
| Field | Value |
|---|---|
| **Notes** | No unified global insect body mass database exists; patchwork from entomology journals. Key literature: Chown & Gaston, Peters (1983), Moran & Woods. Dryad and Zenodo searches are primary discovery strategy. |

---

### 1.23 Reptile-Trait Database

| Field | Value |
|---|---|
| **Taxonomic scope** | Reptiles |
| **Body size variables** | Body mass, SVL, max body size |
| **Citation** | Grimm A, et al. (UNVERIFIED — confirm existence and primary citation for a formal "Reptile-Trait" database) |
| **Notes** | UNVERIFIED — a formal unified reptile trait database analogous to AmphiBIO may exist; search Dryad for "reptile trait body mass" |

---

## SECTION 2 — Tier 2 Data Repositories to Search Programmatically

These repositories should be queried using the search vocabulary in Section 3. All APIs are REST-based.

---

### 2.01 Dryad Digital Repository

| Field | Value |
|---|---|
| **Base URL** | https://datadryad.org |
| **REST API base** | https://datadryad.org/api/v2 |
| **API docs** | https://datadryad.org/api/v2/docs |
| **Authentication** | None required for search; OAuth for submission |
| **Rate limits** | ~10 requests/second (UNVERIFIED — check current rate limit headers) |
| **Search endpoint** | `GET /api/v2/search?q={query}&per_page=100&page={n}` |
| **Body mass approach** | Keyword search in title + abstract; iterate search_terms vocabulary; paginate; filter by keyword in dataset metadata |
| **Known body mass datasets** | Many mammal, bird, fish datasets present; use Section 3 vocabulary |
| **Format** | JSON response; `results` array with dataset metadata |
| **Notes** | Same API as used by DryadPlantTraits; directly applicable; use `dryad_api.R` pattern from DryadPlantTraits |

---

### 2.02 Zenodo

| Field | Value |
|---|---|
| **Base URL** | https://zenodo.org |
| **REST API base** | https://zenodo.org/api |
| **API docs** | https://developers.zenodo.org |
| **Authentication** | None for read; personal access token for deposit |
| **Rate limits** | 60 requests/minute for anonymous; 100/minute for authenticated (UNVERIFIED — confirm current limits) |
| **Search endpoint** | `GET /api/records?q={query}&type=dataset&size=100&page={n}` |
| **Body mass approach** | Use `type=dataset` filter + body mass query terms; filter `resource_type.type = "dataset"` |
| **Known body mass datasets** | Vertebrate body mass compilations frequently deposited here |
| **Format** | JSON; `hits.hits` array |
| **Notes** | DryadPlantTraits already has a working Zenodo client at `providers/zenodo/`; adapt directly |

---

### 2.03 Figshare

| Field | Value |
|---|---|
| **Base URL** | https://figshare.com |
| **REST API base** | https://api.figshare.com/v2 |
| **API docs** | https://docs.figshare.com |
| **Authentication** | None for public search; personal token for private content |
| **Rate limits** | Undocumented; be conservative (~1 request/second) (UNVERIFIED) |
| **Search endpoint** | `POST /v2/articles/search` with JSON body `{"search_for": "{query}", "item_type": 3}` (item_type 3 = dataset) |
| **Body mass approach** | POST-based search; set `item_type = 3`; paginate with `offset` and `limit` |
| **Known body mass datasets** | AVONET data on Figshare; many mammal/bird mass supplementaries |
| **Format** | JSON array of article objects |
| **Notes** | Many ecology data papers deposit supplementary files here; high discovery value |

---

### 2.04 OSF (Open Science Framework)

| Field | Value |
|---|---|
| **Base URL** | https://osf.io |
| **REST API base** | https://api.osf.io/v2/ |
| **API docs** | https://developer.osf.io |
| **Authentication** | None for public; token for private |
| **Rate limits** | 100 requests/minute (UNVERIFIED) |
| **Search endpoint** | `GET /v2/search/?q={query}&filter%5Bcategory%5D=data` |
| **Body mass approach** | Search by keyword; filter for data category |
| **Known body mass datasets** | Variable; less systematic than Dryad/Zenodo for ecology |
| **Format** | JSON API format |
| **Notes** | Less comprehensive for ecological datasets than Dryad/Zenodo; lower priority |

---

### 2.05 PANGAEA

| Field | Value |
|---|---|
| **Base URL** | https://www.pangaea.de |
| **REST API** | https://www.pangaea.de/api/ (UNVERIFIED — confirm current API endpoint) |
| **Search** | Elasticsearch-based: `https://www.pangaea.de/search?q={query}&format=json` (UNVERIFIED) |
| **Authentication** | None for public |
| **Body mass approach** | Marine and polar biology body mass datasets; search "body mass", "wet weight fish", "zooplankton size" |
| **Known body mass datasets** | Marine fish, zooplankton body size, polar bear mass, whale body mass from ship surveys |
| **Format** | JSON with dataset metadata and parameter lists |
| **Notes** | Especially valuable for marine organisms; zooplankton, fish, marine mammals |

---

### 2.06 KNB (Knowledge Network for Biocomplexity)

| Field | Value |
|---|---|
| **Base URL** | https://knb.ecoinformatics.org |
| **REST API** | Solr-based search: `https://knb.ecoinformatics.org/knb/d1/mn/v2/query/solr/?q={query}` (UNVERIFIED) |
| **Authentication** | None for public search |
| **Body mass approach** | Search for body mass in ecological datasets; LTER-adjacent data frequently deposited here |
| **Known body mass datasets** | LTER monitoring data including fish and mammal masses |
| **Notes** | Primarily US-focused; DataONE network member — DataONE API may provide broader search across KNB + others |

---

### 2.07 EDI (Environmental Data Initiative)

| Field | Value |
|---|---|
| **Base URL** | https://edirepository.org |
| **REST API** | `https://pasta.edirepository.org/package/search/eml?q={query}` (UNVERIFIED — confirm endpoint) |
| **Authentication** | None for search |
| **Body mass approach** | Search EML metadata for body mass, body size, weight |
| **Known body mass datasets** | LTER network ecological monitoring data; fish surveys with mass |
| **Notes** | Primarily US LTER network data; systematic ecology monitoring datasets |

---

### 2.08 Scientific Data (Nature Portfolio)

| Field | Value |
|---|---|
| **Approach** | Not a REST API; search PubMed or journal website |
| **URL** | https://www.nature.com/sdata |
| **Search** | PubMed API: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&journal=sci+data&term=body+mass` |
| **Body mass approach** | Search Scientific Data for data descriptor papers with body mass focus; download supplementary data |
| **Known datasets** | AmphiBIO, various vertebrate body mass papers published as Scientific Data articles |
| **Notes** | Many of the best curated databases are published here; systematic search of Scientific Data titles is high-value |

---

### 2.09 Movebank

| Field | Value |
|---|---|
| **Base URL** | https://www.movebank.org |
| **REST API** | https://www.movebank.org/cms/movebank-content/movebank-api (UNVERIFIED — confirm URL) |
| **Authentication** | Free account required |
| **Body mass variables** | Animal body mass sometimes recorded in Movebank's `animal-mass` field (Darwin Core attribute) |
| **Body mass approach** | Query for studies with `animal-mass` attribute; filter for datasets with mass data |
| **Notes** | Tracking-focused; body mass is supplementary; use `individual.local.identifier` to link mass to trajectories |

---

## SECTION 3 — Search Term Vocabulary for APIs

Organized by theme in a format directly analogous to `DryadPlantTraits/R/search_terms.R`. These terms are designed for REST API keyword searches across Dryad, Zenodo, Figshare, and Scientific Data.

```r
# GlobalBodySize API Search Vocabulary
# Analogous to DryadPlantTraits/R/search_terms.R
# Themes: general_mass, mammal, bird, fish, reptile, amphibian,
#         arthropod, allometry, morphometrics, specimen, data_paper

globalsize_search_seed_terms <- function() {
  data.frame(
    query_term = c(

      # --- General body mass / body size ---
      '"body mass" species dataset',
      '"body size" species dataset',
      '"body weight" animal species',
      '"wet mass" animal',
      '"dry mass" animal',
      '"fat-free mass" animal',
      '"live weight" species',

      # --- Mammal body mass ---
      '"mammal body mass"',
      '"mammal* mass" trait',
      '"rodent body mass"',
      '"bat body mass"',
      '"carnivore body mass"',
      '"ungulate body mass"',
      '"primate body mass"',
      '"marsupial body mass"',

      # --- Bird body mass / morphology ---
      '"bird body mass"',
      '"avian body mass"',
      '"avian morphology" mass',
      '"bird morphometrics"',
      '"passerine body mass"',
      '"raptor body mass"',

      # --- Fish body mass / length-weight ---
      '"fish body mass"',
      '"length-weight relationship" fish',
      '"fish wet mass"',
      '"fish weight" species dataset',
      '"length weight" fish species data',
      '"teleost body mass"',
      '"elasmobranch body mass"',

      # --- Reptile body mass ---
      '"reptile body mass"',
      '"snake body mass"',
      '"lizard body mass"',
      '"herpetofauna body size"',
      '"squamate body mass"',

      # --- Amphibian body mass ---
      '"amphibian body mass"',
      '"frog body mass"',
      '"salamander body mass"',
      '"anuran body size"',

      # --- Insect / arthropod body mass ---
      '"insect body mass"',
      '"arthropod body size"',
      '"beetle body mass"',
      '"invertebrate body mass"',
      '"insect morphometrics"',
      '"ant body mass"',
      '"zooplankton body mass"',
      '"zooplankton body size"',

      # --- Allometry (metabolic scaling) ---
      '"body mass allometry"',
      '"metabolic scaling" body mass',
      '"allometric scaling" mass exponent',
      '"interspecific allometry" body mass',
      '"intraspecific allometry" mass',
      '"mass scaling" species',

      # --- Morphometrics ---
      '"morphometric" body mass species',
      '"skull morphometrics" mammal',
      '"museum specimen" body mass',
      '"natural history collection" measurements',

      # --- Plant body size analogues ---
      '"seed mass" species global',
      '"plant height" species trait data',
      '"above-ground biomass" species',

      # --- Data paper framing ---
      '"body mass database"',
      '"body size database"',
      '"body mass compilation" species',
      '"body size compendium" vertebrate',
      '"life history" body mass data',
      '"trait database" body mass',
      '"functional traits" body mass vertebrate',
      '"species traits" body mass dataset'

    ),
    theme = c(
      "general_mass", "general_mass", "general_mass",
      "general_mass", "general_mass", "general_mass", "general_mass",
      "mammal", "mammal", "mammal", "mammal", "mammal", "mammal", "mammal", "mammal",
      "bird", "bird", "bird", "bird", "bird", "bird",
      "fish", "fish", "fish", "fish", "fish", "fish", "fish",
      "reptile", "reptile", "reptile", "reptile", "reptile",
      "amphibian", "amphibian", "amphibian", "amphibian",
      "arthropod", "arthropod", "arthropod", "arthropod", "arthropod",
      "arthropod", "arthropod", "arthropod",
      "allometry", "allometry", "allometry", "allometry", "allometry", "allometry",
      "morphometrics", "morphometrics", "morphometrics", "morphometrics",
      "plant_size", "plant_size", "plant_size",
      "data_paper", "data_paper", "data_paper", "data_paper",
      "data_paper", "data_paper", "data_paper", "data_paper"
    ),
    taxon_focus = c(
      "cross_taxon", "cross_taxon", "cross_taxon",
      "cross_taxon", "cross_taxon", "cross_taxon", "cross_taxon",
      "mammalia", "mammalia", "mammalia", "mammalia", "mammalia",
      "mammalia", "mammalia", "mammalia",
      "aves", "aves", "aves", "aves", "aves", "aves",
      "pisces", "pisces", "pisces", "pisces", "pisces", "pisces", "pisces",
      "reptilia", "reptilia", "reptilia", "reptilia", "reptilia",
      "amphibia", "amphibia", "amphibia", "amphibia",
      "arthropoda", "arthropoda", "arthropoda", "arthropoda", "arthropoda",
      "arthropoda", "arthropoda", "arthropoda",
      "cross_taxon", "cross_taxon", "cross_taxon", "cross_taxon",
      "cross_taxon", "cross_taxon",
      "cross_taxon", "cross_taxon", "cross_taxon", "cross_taxon",
      "plantae", "plantae", "plantae",
      "cross_taxon", "cross_taxon", "cross_taxon", "cross_taxon",
      "cross_taxon", "cross_taxon", "cross_taxon", "cross_taxon"
    ),
    stringsAsFactors = FALSE
  )
}
```

**Total terms: 66** (6 broad + 8 mammal + 6 bird + 7 fish + 5 reptile + 4 amphibian + 8 arthropod + 6 allometry + 4 morphometrics + 3 plant + 8 data_paper)

**Notes on API usage:**
- For Dryad/Zenodo: URL-encode and pass as `q=` parameter
- For Figshare: pass as `search_for` in JSON POST body
- Quoted phrases enforce exact phrase match on most APIs — test each API's quote handling before production run
- Plural wildcards (e.g., `mammal*`) may not work on all REST APIs; test per-platform

---

## SECTION 4 — GBIF Body Size via rgbif

### 4.1 Does GBIF MeasurementOrFact contain meaningful body size data?

**Assessment: Marginally useful; high effort, low yield for most taxa.**

The Darwin Core `MeasurementOrFact` (MoF) extension allows publishers to include quantitative measurements alongside occurrence records. However:

- Only a **small minority** of GBIF publishers include MoF data
- Body mass is one of the less commonly published measurements (compared to reproductive state or phenological stages)
- Coverage is strongly biased toward **vertebrates monitored by systematic programs** (e.g., bird banding, fish surveys, some mammal trapping programs)
- The **GBIF download API** (v1) supports downloading MoF extension data, but it requires occurrence downloads with extension inclusion — currently only available through GBIF's download portal or `occ_download()` in `rgbif`

### 4.2 How to query via rgbif

```r
library(rgbif)

# Step 1 — Search for occurrences with MeasurementOrFact
# There is no direct GBIF search filter for "has body mass"
# Strategy: download occurrence + MoF for target taxa

# Example: mammals with body mass
download_key <- occ_download(
  pred("taxonKey", 359),          # Mammalia class key (UNVERIFIED — confirm GBIF taxon key)
  pred("hasGeospatialIssue", FALSE),
  format = "DWCA"                 # Darwin Core Archive includes MoF extension
)

# After download completes:
library(finch)   # or use archive extraction manually
# Parse the MeasurementOrFact.txt file from the DWCA zip
# Filter for measurementType matching "body mass", "mass", "weight"

# Step 2 — GBIF species API does not expose MoF — must use occurrence API
# rgbif::occ_search() does NOT return MoF; must use full DWCA download
```

### 4.3 Coverage assessment

| Taxon group | Estimated MoF body mass records in GBIF | Recommendation |
|---|---|---|
| Birds (banding programs) | Low–moderate; some ringing programs include mass | Worth checking |
| Mammals | Low; trapping programs occasionally include mass | Spot-check |
| Fish | Low; fisheries survey data sometimes included | Check PANGAEA instead |
| Reptiles / Amphibians | Very low | Not recommended as primary source |
| Insects | Essentially zero at present | Skip |
| Plants | Rare (seed mass occasionally) | Use TRY instead |

### 4.4 Known example datasets with body mass in GBIF

- Some bird banding datasets (e.g., from European ringing centers) include body mass in MoF — UNVERIFIED on specific publisher names
- Some NEON (National Ecological Observatory Network) data submitted to GBIF includes body mass — UNVERIFIED
- Mammal trapping datasets from some LTER sites may include mass — UNVERIFIED

**Verdict:** GBIF MoF is worth a targeted scan using DWCA download + MoF parsing, but should not be the primary strategy. Use as supplemental, particularly for well-monitored vertebrate groups.

---

## SECTION 5 — Specialist Web Sources (Manual or Custom Intake)

These sources require manual download, web scraping with permission, or bespoke API wrappers not covered by existing R packages.

---

### 5.1 Natural History Museum Collections (Digitized)

| Institution | Portal | Body mass availability | Notes |
|---|---|---|---|
| NMNH (Smithsonian) | https://collections.nmnh.si.edu | Mammals: sometimes on specimen tags; inconsistent | Accessible via iDigBio API or direct portal |
| AMNH | https://portal.amnh.org | Similar to NMNH; vertebrate specimens | Variable field completeness |
| NHM London | https://data.nhm.ac.uk | Data portal with API; some body mass in specimen data | `nhmr` package (UNVERIFIED — confirm package name) |
| MVZ Berkeley | https://vertnet.org (via VertNet) | Mammal specimens with occasional mass | Query via `rvertnet` |
| FMNH Chicago | https://db.fieldmuseum.org | Mammal and bird specimens | VertNet member |
| MNHN Paris | https://www.gbif.fr (via GBIF) | Variable | French national collection |

**Strategy for museum collections:** Use `rvertnet` as primary programmatic access point, then supplement with direct portal searches for NMNH and NHM.

---

### 5.2 Government Ecological Monitoring Programs

| Program | Taxa | Body mass data | Access |
|---|---|---|---|
| NEON (National Ecological Observatory Network) | Mammals, birds, fish, macroinvertebrates | Mammal body mass systematically collected | `neonUtilities` R package; https://data.neonscience.org |
| LTER Network (USA) | Multiple taxa per site | Variable by site — some fish and mammal mass data | EDI repository; site-specific portals |
| North American Breeding Bird Survey (BBS) | Birds | Count data only; no body mass | Not a mass data source |
| Christmas Bird Count (CBC) | Birds | Count data only; no body mass | Not a mass data source |
| FishBase Monitoring Networks | Fish | Via FishBase; LW relationships | See 1.07 |
| ICES DATRAS (European fish trawl surveys) | Fish | Body mass of individual fish sometimes recorded | https://www.ices.dk/data/data-portals/Pages/DATRAS.aspx (UNVERIFIED) |

---

### 5.3 Fisheries Databases

| Database | Body mass data | Access |
|---|---|---|
| FishBase | LW parameters → derived mass | `rfishbase` R package |
| SeaLifeBase | Marine invertebrate and non-fish vertebrate LW | `rsealifebase` (UNVERIFIED) |
| RAM Legacy Stock Assessment Database | Fisheries biomass (population, not individual); some size-at-age | https://www.ramlegacy.org; `ramlegacy` R package (UNVERIFIED — confirm package) |
| ICES Stock Assessment Database | Fisheries; length-weight used in stock assessment | Manual download from ICES |
| DATRAS (ICES trawl surveys) | Individual fish weight from trawl surveys | ICES API (UNVERIFIED) |
| OBIS (Ocean Biodiversity Information System) | MoF extension (similar to GBIF); some body mass | https://obis.org; `robis` R package |

---

### 5.4 Entomology and Arthropod Databases

| Database | Scope | Notes |
|---|---|---|
| SCAN (Symbiota Collections of Arthropods Network) | Arthropod museum specimens | Body mass rarely recorded; morphology (wing length, body length) more common |
| iDigBio | All digitized natural history collections | Search for arthropod records; mass rarely included |
| Global Ant Biodiversity Informatics (GABI) | Ants | Distribution focus; some morphometric data |
| Ant Traits Database | Ant morphometrics | UNVERIFIED — search Dryad/Zenodo for "ant traits database" |
| Bee traits databases (various) | Bees | Body mass and body size for some bee species; UNVERIFIED on unified database |

---

## SECTION 6 — Data Integration Challenges

The following are the top 7 critical challenges for body mass harmonization in GlobalBodySize, in approximate order of severity.

---

### 6.1 Ontological Ambiguity (Wet / Dry / Fat-Free / Lean Mass)

**Severity: Critical**

Different sources report fundamentally different quantities:
- **Wet mass** (live body mass): most ecological databases (PanTHERIA, EltonTraits, AVONET)
- **Dry mass**: sometimes used for invertebrates, particularly in energy budget studies
- **Fat-free mass**: physiology and adiposity studies
- **Eviscerated mass**: museum collections after organ removal
- **Ethanol-preserved mass**: museum specimens fixed in alcohol (mass is altered by preservation chemistry)

**Action required:** Create a controlled vocabulary for `mass_type` field in the harmonized schema. Never merge wet and dry mass without explicit conversion or flagging. Conversion factors exist for some taxa but are variable (see Peters 1983).

---

### 6.2 Life Stage Confusion (Juvenile vs. Adult vs. Neonatal)

**Severity: Critical**

Most databases report adult body mass, but:
- Some museum specimens are juveniles without explicit age-class annotation
- FishBase length-weight relationships span all size classes; "maximum mass" vs. "typical adult mass" differ substantially
- For insects, adult mass at eclosion vs. mass at death varies significantly
- Some allometric studies use all available specimens regardless of age class

**Action required:** Require `life_stage` field; default to "adult" only when explicitly stated; flag unknown stage records.

---

### 6.3 Sex Differences and Sexual Dimorphism

**Severity: High**

Mammal databases often report sex-specific mass or an unstated aggregate:
- Many PanTHERIA entries are male or female biased depending on original study
- Birds show strong reversed or standard sexual size dimorphism (raptors vs. hummingbirds)
- Fish mass-at-length relationships are often sex-aggregated but sex ratio in samples affects estimates

**Action required:** Require `sex` field (male / female / mixed / unknown); report sex-specific means where available; harmonize to mean-of-means with sample weighting where possible.

---

### 6.4 Measurement Method (Live vs. Preserved vs. Estimated)

**Severity: High**

- Live mass: measured from live animals in the field or captivity
- Preserved mass: museum specimens (altered by preservation medium)
- Estimated mass: derived from length-weight relationships (most fish), allometric equations, or diet-mass models
- Literature-compiled means: meta-analytical aggregations of any of the above

**Action required:** Implement a `mass_measurement_method` field with controlled vocabulary: `direct_live`, `direct_preserved`, `derived_lw`, `derived_allometric`, `literature_mean`.

---

### 6.5 Taxonomic Name Resolution Across Groups

**Severity: High**

No single taxonomic authority covers all animal groups and plants:
- Mammals: Wilson & Reeder, ASM Mammal Diversity Database
- Birds: BirdLife, eBird/Clements, HBW — these taxonomies disagree on ~2,000+ species splits/lumps
- Fish: FishBase taxonomy (Catalog of Fishes); Eschmeyer's Catalog
- Reptiles: Reptile Database (Uetz et al.)
- Amphibians: AmphibiaWeb, Frost et al. (American Museum Novitates)
- Plants: TNRS, World Flora Online, GBIF Backbone

**Action required:** Run all taxonomic names through a multi-group resolver; `taxize` R package supports many of these. Retain original source name, matched name, and match confidence. Store `taxon_id_backbone` referencing GBIF backbone taxon key as a cross-group denominator.

---

### 6.6 Units (g, kg, mg, oz, lbs)

**Severity: Moderate** (fixable with careful implementation)

- Most ecology databases use grams (g)
- Some fish databases use kilograms; some older literature uses pounds or ounces
- Zooplankton may use micrograms (µg) or milligrams (mg)
- Plant seed mass frequently in milligrams (mg)

**Action required:** Standardize all mass to **grams (g)** as the canonical unit in harmonized database. Record `original_unit` and `original_value` alongside converted value. Flag any converted values derived from suspected unit mismatches.

---

### 6.7 Spatial and Temporal Bias

**Severity: Moderate–High**

- Most body mass data are from **temperate North America and Europe** — systematic underrepresentation of tropics
- Recent decades over-represented; historical body mass data are sparse and may reflect different population conditions
- Island populations often excluded or conflated with mainland
- Captive animal masses (zoos, wildlife centers) may differ substantially from wild

**Action required:** Attach `decimal_latitude`, `decimal_longitude`, `year_measured`, `captive_wild` fields to all records where available. Calculate geographic bias metrics before publishing. Flag captive-source records.

---

## SECTION 7 — Priority Ranking

Rank of top 10 data sources for initiating the GlobalBodySize project, based on: (a) taxonomic coverage, (b) programmatic accessibility, (c) data quality, (d) ease of harmonization.

| Rank | Data Source | Taxon Coverage | Rationale |
|---|---|---|---|
| **1** | **PanTHERIA** | Mammals (~5,400 spp) | Best-documented mammal body mass source; standardized; direct download; highest citation authority |
| **2** | **AVONET** | Birds (~10,000+ spp) | Highest-quality avian morphology; standardized protocols; largest specimen base |
| **3** | **EltonTraits 1.0** | Birds + Mammals | Fills gaps; widely used; complements PanTHERIA and AVONET; provides cross-check |
| **4** | **rfishbase (FishBase)** | Fish (>33,000 spp) | Programmatic R access; largest fish coverage by far; LW-derived mass acceptable with uncertainty |
| **5** | **AmphiBIO** | Amphibians (~6,776 spp) | Best available for amphibians; download straightforward; known gaps manageable |
| **6** | **TRY Plant Trait Database** | Plants (~280,000+ spp partial) | Essential for plant size proxies (seed mass, height, plant mass); registration required but free |
| **7** | **Dryad + Zenodo programmatic search** | Cross-taxon | Extends coverage into reptiles, insects, specialized groups; proven pipeline from DryadPlantTraits |
| **8** | **AnAge** | Vertebrates broad | Cross-taxonomic cross-check; useful for vertebrate mass gaps especially in unusual taxa |
| **9** | **Reptile size databases (Meiri/Feldman series)** | Reptiles | Best currently available for reptiles; requires manual integration from papers |
| **10** | **VertNet (rvertnet)** | Vertebrates — museum specimens | Provides individual-level specimen data for gap-filling and cross-checking database means |

**Not ranked but strategically important:**
- Arthropod body size: no tier-1 database exists; Dryad/Zenodo search is the only scalable strategy
- GBIF MoF: worth a targeted scan but unlikely to be a primary contributor

---

## Appendix A — Suggested R Package Dependency Summary

| R Package | Purpose | CRAN status |
|---|---|---|
| `rfishbase` | FishBase access | On CRAN |
| `rredlist` | IUCN Red List API | On CRAN |
| `rgbif` | GBIF occurrences + MoF | On CRAN |
| `rvertnet` | VertNet museum specimen search | On CRAN (UNVERIFIED — confirm maintained) |
| `taxize` | Cross-group taxonomic name resolution | On CRAN |
| `httr2` or `httr` | REST API calls (Dryad, Zenodo, Figshare, OSF) | On CRAN |
| `jsonlite` | Parse JSON API responses | On CRAN |
| `data.table` | Fast in-memory data harmonization | On CRAN |
| `robis` | OBIS ocean biodiversity API | On CRAN (UNVERIFIED — confirm) |
| `neonUtilities` | NEON ecological monitoring data | On CRAN |
| `finch` | Parse Darwin Core Archives (GBIF downloads) | On CRAN (UNVERIFIED — confirm) |

---

## Appendix B — Recommended Schema Fields for Harmonized Database

Minimum required fields for each body mass record in the unified GlobalBodySize dataset:

```
species_name_original       # verbatim from source
species_name_resolved       # after TNRS/taxize resolution  
taxon_key_gbif              # GBIF backbone taxon key
class                       # Mammalia, Aves, Reptilia, Amphibia, Actinopterygii, Insecta, etc.
order
family
body_mass_g                 # standardized to grams
body_mass_original          # original value before conversion
body_mass_unit_original     # g, kg, mg, lb, oz
mass_type                   # wet_mass, dry_mass, fat_free_mass, eviscerated, unknown
life_stage                  # adult, juvenile, unknown
sex                         # male, female, mixed, unknown
mass_measurement_method     # direct_live, direct_preserved, derived_lw, derived_allometric, literature_mean
n_individuals               # sample size (1 if individual record; NA if unknown)
source_database             # PanTHERIA, AVONET, FishBase, AmphiBIO, etc.
source_doi                  # DOI of originating data paper or database
year_measured               # year of measurement (NA if unknown)
decimal_latitude            # if available
decimal_longitude           # if available
captive_wild                # captive, wild, unknown
notes                       # free text
```

---

*Document ends. All UNVERIFIED entries require independent confirmation before use in publications or data products.*
