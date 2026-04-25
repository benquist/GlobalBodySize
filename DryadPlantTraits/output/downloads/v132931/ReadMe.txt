Please also cite Hein et al. (2021) Drought sensitivity of Empetrum nigrum shrub growth at the species’ southern lowland distribution range margin - Plant Ecology https://doi.org/10.1007/s11258-020-01107-z when using any or part of these datasets

Datasets:
'clim_Norderney2.csv' contains the climate data (see publication for sources)

'Plant growth data.csv' contains the shoot length measurements in mm for each subsite (A, B, C, D), name of researcher (pi/ pi_full), and coordinates and elevation (m a.s.l.) of the subsites in decimal degrees (latitude/longitude/elevation).

'CNS.csv' contains the measurements of carbon, nitrogen, and sulfur content (%) in leaves of Empetrum nigrum formed during the growing season of 2017. 'A', 'B', 'C', and 'D' in sample names refers to the sites (see publication). Samples were measured in duplo. 

'Soil data combined.csv' contains the measured soil parameters (pH measured in CaCl2 solution (pH_CaCl) and in distilled H2O (pH_H2O), electric conductivity (Conductivity), and soil moisture content (Moisture.pct))


Code:
'climate_data.R' contains the calculation of seasonal means and standardization of the climate data.

'mixed_models.R' contains the code for the linear mixed effects model analyses.

'plotting_lme.R contains the code for Figure 2.

'growth_level.R' contains the statistical analyses of the raw growth data (growth level comparison) as well as the code for Figure 3.

'CNS.R' contains the statistical analyses of the leaf C and N data, as well as the code for Figure 4.

'soil_data.R' contains the statistical analyses of the soil parameters, as well as the code for Figure 5.