suppressMessages({
  library(baad.data); library(dplyr); library(tidyr)
  library(V.PhyloMaker2); library(ape); library(caper); library(smatr)
  baad <- baad.data::baad_data(); dat <- baad$data
  dat <- dat |> mutate(clade = case_when(grepl("A$", pft) ~ "Angiosperm", grepl("G$", pft) ~ "Gymnosperm", TRUE ~ NA_character_))
  d_lf <- dat |> filter(m.to > 0, m.lf > 0)
  d_al <- dat |> filter(m.to > 0, a.lf > 0)
  sp_lf <- d_lf |> filter(!is.na(speciesMatched), !is.na(family)) |>
    group_by(speciesMatched) |>
    summarise(log_mto=mean(log10(m.to)), log_mlf=mean(log10(m.lf)), family=first(family), .groups="drop") |>
    drop_na() |> mutate(sp_phylo=gsub(" ","_",speciesMatched))
  sp_al <- d_al |> filter(!is.na(speciesMatched), !is.na(family)) |>
    group_by(speciesMatched) |>
    summarise(log_mto=mean(log10(m.to)), log_al=mean(log10(a.lf)), family=first(family), .groups="drop") |>
    drop_na() |> mutate(sp_phylo=gsub(" ","_",speciesMatched))
  cat("sp_lf n species:", nrow(sp_lf), "\n")
  cat("sp_al n species:", nrow(sp_al), "\n")
  sl <- bind_rows(
    sp_lf |> dplyr::select(species=speciesMatched, family),
    sp_al |> dplyr::select(species=speciesMatched, family)
  ) |> distinct(species, .keep_all=TRUE) |>
    mutate(genus=sub(" .*","",species)) |>
    dplyr::select(species, genus, family)
  cat("Unique species for phylo:", nrow(sl), "\n")
  tree <- tryCatch({
    r <- V.PhyloMaker2::phylo.maker(sp.list=sl, tree=GBOTB.extended.TPL, nodes=nodes.info.1.TPL, scenarios="S3")
    r$scenario.3
  }, error=function(e){cat("tree error:", conditionMessage(e), "\n"); NULL})
  if (!is.null(tree)) {
    cat("Tree tips:", ape::Ntip(tree), "\n")
    cat("LF matched:", sum(sp_lf$sp_phylo %in% tree$tip.label), "of", nrow(sp_lf), "\n")
    cat("AL matched:", sum(sp_al$sp_phylo %in% tree$tip.label), "of", nrow(sp_al), "\n")
  }
})
