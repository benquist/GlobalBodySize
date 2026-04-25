

GENERAL INFORMATION

1. Title of Dataset: Shoot senescence in herbaceous perennials of the temperate zone

2. Author Information
	Corresponding Investigator 
		Name: Tomas Herben
		Institution: Institute of Botany, Czech Academy of Science, Pruhonice, Czech Republic 
	


Date of data collection: 2020

Geographic location of data collection: Prague, Czech Reepublic

5. Funding sources that supported the collection of the data: Grant Agency of the Czech Republic

6. Recommended citation for this dataset: Maskova et al. (2022), Data from: Shoot senescence in herbaceous perennials of the temperate zone, Dryad, Dataset


DATA & FILE OVERVIEW

1. Description of dataset

We fitted the spline function on each individual of each species using the function smooth.spline. We then determined the overall shape of the senescence trajectory for each species by averaging the values of these functions for all meaningful dates for the given species. We used these average predicted values for the species to perform interpolation between measurement dates to obtain approximate dates at which the average individual reached specific fractions of its maximum size. Maximum size was calculated as the mean of the maximum sizes of all individuals of the species (i.e. it is not necessarily the maximum of the spline curve). We extracted three parameters from these predicted values: (i) senescence date, measured in days and defined as the first day in the season in which the predicted value reached 50% of the maximum size of the species; it was undefined for species that never reached 50% of their maximum size (two species); (ii) senescence pace, defined as the inverse of the number of days (i.e. with units day-1) elapsed between the last predicted value being equal to 95% of the maximum size and the first predicted value being equal to 5% of the maximum size; in the few species (nine species) that never reached 5% of their maximum size, we calculated the pace in the same way from the existing part of the senescence curve; and (iii) senescence shape, defined as log(C/D), where C is the difference between the dates on which the predicted value reached 50% and 5% of the maximum size of the species, D is the difference between the dates on which the predicted value reached 50% and 95% of the maximum size of the species. It is a dimensionless number, with positive values indicating concave (in the mathematical sense) shapes of the senescence trajectory, i.e. increasing absolute values of senescence pace over time (positive senescence sensu Baudisch et al. 2013) and vice versa. It was undefined for species which did not reach 5% of their maximum size (nine species). Finally, to express the degree to which individuals of one species differed in their senescence trajectories, we used standard deviation of the date on which individuals reached 50% of their maximum size as the fourth senescence parameter (units: days). This parameter is further called senescence asynchrony, following usage of the term in literature. 


2. File List: 
	File 1 Name: senescence_data.txt
	File 1 Description: Seenescence parameters for individual species


	


DATA-SPECIFIC INFORMATION FOR: senescence_data.txt 

1. Number of variables: 8

2. Number of cases/rows: 238

3. Variable List: 

Variable name	Definition	Units
Species	Species name	
Day_95%	Day of the year when the individuals on average reach 95% of their maximum size	Day of the year
Day_75%	Day of the year when the individuals on average reach 75% of their maximum size	Day of the year
Day_05%	Day of the year when the individuals on average reach 05% of their maximum size	Day of the year
Senescence_date	Senescence date: Day of the year when the individuals on average reach 50% of their maximum size	Day of the year
Senescence_pace	Senescence pace: inverse of the number of days elapsed between the last average value being equal to 95% of the maximum size and the first average value being equal to 5% of the maximum size	day-1
Senescence_shape	"Senescence shape: log(C/D), where C is the difference between the dates on which the predicted value reached 50% and 5% of the maximum size of the species, D is the difference between the dates on which the predicted value reached 50% and 95% of the maximum size of the species"	dimensionless
Senescence_asynchrony	standard deviation of the date on which individuals reached 50% of their maximum size 	day

