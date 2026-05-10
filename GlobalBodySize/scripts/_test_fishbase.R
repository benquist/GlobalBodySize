library(rfishbase)

## Get species binomials
fb <- rfishbase::load_taxa()
cat("load_taxa rows:", nrow(fb), "\ncols:", paste(names(fb), collapse=", "), "\n")
cat("example:", paste(head(fb$Species, 5), collapse=", "), "\n")

## Get weight directly from species table (subset first)
sp_sample <- fb$Species[1:10]
sp_data   <- rfishbase::species(species_list = sp_sample,
                                 fields = c("Species", "Weight", "Length"))
cat("species() result:\n")
print(sp_data)
