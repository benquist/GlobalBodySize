# READ ME
# This code is part of an RStudio project called "Link-scaling.Rproj" and accompanies the paper "Linking scaling laws across eukaryotes"
# by: I.A. Hatton, A.P. Dobson, D. Storch, E.D. Galbraith, M. Loreau

# By opening the "Link scaling.Rproj" file and running all the "Analysis.R" code, the analysis described in the paper can be reproduced, or altered in various ways. 
# The "Analysis.R" code calls a number of functions (from "Funx.R") and reads in the following data files:
# Metabolism.csv 
# Abundance.csv 
# Growth.csv 
# Mortality.csv
# These data files are located in the "Data" folder in the "Link-scaling" folder along with "References.csv" which includes all references to source data in the above-listed data files.

# The tempcorr() function allows the specification for how basal metabolism is temperature corrected to a particular temperature, using either published Q10 values or the Arrhenius equation with a standard activation energy.

# The aggre() function allows specifying how multiple measures of a species are aggregated (using functions of min, max, mean or geometric mean).

# In both of the above functions, we can also specify which groups are included or excluded in these functions indicated at plot2. Plot2 lists numbered major groups in each dataset as follows:
# 1 - Herbivore mammal
# 2 - Carnivore mammal
# 3 - Protist
# 4 - Plant
# 5 - Invertebrate
# 6 - Ectotherm vertebrate
# 7 - Bird
# 8 - Bacteria
# 9 - Omnivore mammal

# The combVar() function allows basic variables (metabolism, abundance, growth and mortality) to be combined through multiplication, either through direct species matches, or if matches are not available, at the order-level or major group-level using regression predictions.

# The regtable() function outputs regression summary statistics equivalent to Tables S1 to S8 in the Supplementary Data file (for the default function parameters). The taxonomic order-level regressions are returned based on the data meeting the minimum number of data points (e.g. len=15) and the minimum mass range (e.g. rang=100) specified. Order-level regressions can be excluded from results by setting orderadd=FALSE. 

# A single regression on user-specified data can be returned from the segslope() function, which can also draw the regression line on plotted data. More details on the functions are included in "Funx.R". More detailed methods are included in the Supplementary Information file.
