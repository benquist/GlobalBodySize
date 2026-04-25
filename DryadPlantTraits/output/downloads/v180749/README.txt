This README.txt file was generated on 24 May 2022 by Alice Stears

GENERAL INFORMATION

1. Title of Dataset: Water availability dictates how plant traits predict demographic rates

2. Author Information

	A. Principal Investigator Contact Information
		Name: Alice Stears
		Institution: University of Wyoming
		Email: alice.e.stears@gmail.com

	B. Co-authors: Peter Adler, Dana Blumenthal, Julie Kray, Kevin Mueller, Troy Ocheltree, Kevin Wilcox, Daniel Laughlin

3. Date of data collection
	
	Demographic Data: Chart Quadrats were mapped between May and August in each year from 1997 to 2010. 
	
	Trait Data: Species-level mean trait values were calculated from samples collected between 2014 and 2019. 

4. Geographic location of data collection
	
	Demographic Data: Chart quadrats were located at the Central Plains Experimental Range in Nunn, Colorado, USA. (40.8 degrees N / -110.8 degrees W)
	
	Trait Data: In most cases, trait values were calculated from samples collected at the Central Plains Experimental Range. If not, they were measured from samples collected at the following locations: 
		- High Plains Grasslands Research Station, Cheyenne, WY, USA (HPGRS; 41.2 degrees N / -104.9 degrees W)
		- Fort Keogh Livestock and Range Research Laboratory, Miles City, Montana, USA (Ft. Keogh; 46.4 degrees N / -105.8 degrees W)
		- USDA Sheep Station, Dubois, Idaho, USA (Sheep Station; 44.3 degrees N / -112.2 degrees W)
		- Hays State University Pasture, Hays, KS, USA (Hays; 38.8 degrees N / -99.4 degrees W)

ACCESS INFORMATION

1. Links to publications that cite or use the data

	 These data were included in the publication "Water availability dictates how plant traits predict demographic rates", published in Ecology.

2. Relationships to ancillary data sets

	Demographic data: 
		Growth and survival data included in the two demographic data files were calculated using raw data from the following publication: 
			Chu, C., J. Norman, R. Flynn, Ni. Kaplan, W. K. Lauenroth, and P. B. Adler. 2013. Cover, density, and demographics of shortgrass steppe plants mapped 1997-2010 in permanent grazed and ungrazed quadrats. Ecology 94:1435.

		This growth and survival information was generated using tracking algorithms that were based off of algorithms used in the following publication: 
			Lauenroth, W. K., and P. B. Adler. 2008. Demography of perennial grassland plants: Survival, life expectancy and life span. Journal of Ecology 96:1023'961032.

	Trait data: 
		Mean leaf and root trait values for species that were collected at the Central Plains Experimental Range were previously published in  the following publication: 
			Blumenthal, D. M., K. E. Mueller, J. A. Kray, T. W. Ocheltree, D. J. Augustine, and K. R. Wilcox. 2020. Traits link drought resistance with herbivore defence and plant economics in semiuc0u8208 arid grasslands: The central roles of phenology and leaf dry matter content. Journal of Ecology 108:2336'962351.

DATA & FILE OVERVIEW

1. File List: 

 	meanTraits.csv
	pointSpeciesSurvData.csv
	polygonSpeciesSurvData.csv

DATA-SPECIFIC INFORMATION FOR "meanTraits.csv"

1. Number of variables: 10

2. Number of rows: 16 (excluding column names)

3. Variable list: 
	"species": the latin binomial name of this species
	"Functional_Group": the functional group of this species; "F" = forb, "G" = graminoid
	"SLA_cm2_g": species-mean specific leaf area in cm^2/g
	"LDMC_g_g"; species-mean leaf dry matter content in g/g
	"RDMC_g_g": species-mean root dry matter content in g/g
	"RTD_g_cm3": species-mean root tissue diameter in cm^3
	"rootDiam_mm": species-mean average root diameter in mm
	"TLP_MPa": species-mean leaf turgor loss point in MPa
	"OtherDataSource": The location where trait samples were collected. If no value, all samples were collected at the Central Plains Experimental Range (CPER). Otherwise, the sampling location is specified for each trait for which samples were not collected at the CPER. If multiple locations are listed for a single trait, the trait value is an average of values from the listed sites. "Ft. Keogh" indicates the Fort Keogh Livestock and Range Experimental Station in Miles City, MT; "Sheep Station" indicates the USDA Sheep Station in Dubois, ID; "Hays" indicates the Hays State University Pasture in Hays, KS; "HPGRS" indicates the High Plains Grasslands Research Station in Cheyenne, WY. 

4. Missing data codes: NA

DATA-SPECIFIC INFORMATION FOR "pointSpeciesSurvData.csv"

1. Number of variables: eight

2. Number of rows: 4,646 (excluding column names)

3. Variable list: 
	"species": The latin binomial name of each observation
	"quad": The name of the chart quadrat where this observation was located
	" year_t": The year when this observation was recorded
	" trackID": A factor that uniquely identifies each observation in each quadrat in each year. If there are multiple observations of the same species in the same quadrat and year, then they have different "trackID" values. An observation retains its trackID as long as it is alive. 
	" x_t": the location of the observation on the x-axis of the quadrat, in meters
	"y_t": the location of the observation on the y-axis of the quadrat, in meters
	"survives_tplus1": A binary variable indicating whether an observation survived to the next year. "1" indicates that the plant survived, while "0" indicates that the plant died. 
	"nearEdge_t": A TRUE/FALSE variable indicating whether the observation is within 5 cm of the quadrat edge. 

4. Missing data codes: NA

DATA-SPECIFIC INFORMATION FOR "polygonSpeciesSurvData.csv"

 1. Number of variables: 10

2. Number of rows: 31,625 (excluding column names)

3. Variable list: 
	"species": The latin binomial name of each observation
	"quad": The name of the chart quadrat where this observation was located
	" year_t": The year when this observation was recorded
	" trackID": A factor that uniquely identifies each observation in each quadrat in each year. If there are multiple observations of the same species in the same quadrat and year, then they have different "trackID" values. An observation retains its trackID as long as it is alive. 
	" x_t": the location of the observation'92s polygon centroid on the x-axis of the quadrat, in meters
	"y_t": the location of the observation'92s polygon centroid on the y-axis of the quadrat, in meters
	"area_t": the basal area of the observation in the current year
	"area_tplus1": the basal area of the observation in the next year, if it survived
	"survives_tplus1": A binary variable indicating whether an observation survived to the next year. "1" indicates that the plant survived, while "0" indicates that the plant died. 
	"nearEdge_t": A TRUE/FALSE variable indicating whether the observation is within 5 cm of the quadrat edge. 

4. Missing data codes: NA