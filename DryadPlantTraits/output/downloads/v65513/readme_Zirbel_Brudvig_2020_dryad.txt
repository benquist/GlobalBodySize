Readme file for data and analysis associated with
Zirbel, C.R. and Brudvig, L.A. (2020)

Trait-environment interactions affect plant establishment success during restoration

Ecology

Please contact Chad Zirbel (crzirbel@gmail.com) with any questions related to this data repository.
The authors ask that they be contacted before publishing work using the following datasets.
When using the following dataset please cite the original paper as well as the data repository.

This repository contains 10 files including data and the R script used to analyze them.
Please see the methods section of Zirbel and Brudvig (2020) for more details on how the following data were collected and analyzed.
Files contained within this repository:
1.	light_data_Zirbel_Brudvig_2020_dryad.csv
2.	herbivory_Zirbel_Brudvig_2020_dryad.csv
3.	sown_density_Zirbel_Brudvig_2020_dryad.csv
4.	seedling_count_Zirbel_Brudvig_2020_dryad.csv
5.	trait_data_Zirbel_Brudvig_2020_dryad.csv
6.	leaf_area_Zirbel_Brudvig_2020_dryad.csv
7.	seed_mass_Zirbel_Brudvig_2020_dryad.csv
8.	soil_moisture_Zirbel_Brudvig_2020_dryad.csv
9.	leaf_CN_Zirbel_Brudvig_2020_dryad.csv
10.	Zirbel_Brudvig_Eco_2020_Rscript.R

####################################################################################################
light_data_Zirbel_Brudvig_2020_dryad.csv

This file contains PAR measurements for each plot at each transect.

##Variables
transect_id: The transect from which each variable was measured
plot: The plot from which each variable was measured
light_available: proportion of available light reaching the ground in each plot
herbivory_Zirbel_Brudvig_2019_dryad.csv
The data file contains herbivory data taken on Echinacea purpurea individuals in each plot.
transect_id: The transect from which each variable was measured
plot: The plot from which each variable was measured
individual: The Echinacea purpurea individual that herbivory was measured on.
Herbivory: percent missing leaf tissue per leaf

##########################################################################################################
sown_density_Zirbel_Brudvig_2020_dryad.csv

This data file contains seeding density for each species in the high and low seeding density treatments

##Variables
species: Species code for the seeded species
seeds_m2: seeds sown per meter^2 in each transect
spp_trt: Whether species was added to the high or low diversity treatment

######################################################################################################
trait_data_Zirbel_Brudvig_2020_dryad.csv

This data file contains functional trait data for each of the species sown into the experiment

##Variables
Species: Species code for each seeded species
Number: Individual number for each species
Source: The geographic source of each individual.
leaf_mass: mass of a single leaf in grams. Used in the SLA calculation
total_root_mass: total belowground biomass of the individual in grams.
total_shoot_mass: total aboveground biomass of the individual in grams.
total_biomass: total biomass (above + below) of the individual in grams.
root_shoot: biomass ratio of roots to shoot.

#########################################################################################################
leaf_area_Zirbel_Brudvig_2020_dryad.csv

This file contains data on leaf area for each individual seeded in the experiment.

##Variables
species: Species code for each seeded species
number	: Individual number for each species
source: The geographic source of each individual
total.leaf.area: Leaf area in cm^2 for a single leaf

#######################################################################################################
seed_mass_Zirbel_Brudvig_2020_dryad.csv

This data file contains seed mass data for each of the seeded species.

##Variables
Species: Species code for each seeded species
seed_mass: seed mass in mg for each species

########################################################################################################
soil_moisture_Zirbel_Brudvig_2020_dryad.csv

The file contains weekly soil moisture data taken at each plot at each transect

##Variables
date: Date measurement was taken on
transect_id: The transect from which each variable was measured
plot1: Percent soil moisture in plot 1
plot2: Percent soil moisture in plot 2
plot3: percent soil moisture in plot 3
plot4: percent soil moisture in plot 4
plot5: percent soil moisture in plot 5

#########################################################################################################
leaf_CN_Zirbel_Brudvig_2020_dryad.csv

This file contains data on leaf carbon and nitrogen for each seeded species in the experiment

##Variables
species: Species code for each seeded species
number	: individual number for each species
source: The geographic source for each species
WEIGHT_g: total dried sample weight in grams
NITROGEN%: percent leaf nitrogen
CARBON%: percent leaf carbon
CN: leaf carbon to nitrogen ratio

#############################################################################################################
Zirbel_Brudvig_Eco_2020_Rscript.R

This R script contains all of code required to perform the analyses in the above manuscript. All analyses were done using R v. 3.6.1
