This README_Lupinus_herbivory2020.txt file was generated on 2022-06-17 by Satu Ramula (satu.ramula@utu.fi)


1. Title of Dataset: Herbivory and traits of Lupinus polyphyllus for Plant Biology

2. Date of data collection (range): 2020-06 - 2020-08

3. Geographic location of data collection: Ruissalo Botanical Garden of the University of Turku, Turku, Finland 

4. Information about funding sources that supported the collection of the data: Academy of Finland (#285746, #331046, #311077)

5. Description of methods used for collection/generation of data: 
Individuals of Lupinus polyphyllus were grown from seed in a greenhouse, and seedlings were planted in the common garden to observe the effects of glyphosate residues on folivory and plant traits during June-August 2020. Leaf consumption between glyphosate-exposed and control plants was explored in a laboratory feeding experiment by using a generalist herbivore, the land snail (Arianta arbustorum, Helicidae).

6. Data files: The data contain 3 files corresponding to different measurements taken from common garden and laboratory experiments for the paper Ramula et al. "Glyphosate residues in soil can modify plant resistance to herbivores through changes in leaf quality". Plant Biology. 


//Data

Herbivory.commongarden.xls
Repeated measures of leaf herbivory in Lupinus polyphyllus based on a common garden experiment in 2020. Missing values are indicated by "n/a", and are due to deaths or lack of herbivory. 
Variable list: 
	Plot – plot ID in the common garden (1-22)
	Subplot – subplot ID (1-44)
	Pop - population ID (6 populations in total)
	Plant.ID - plant ID (1-264)
	Glyphosate – two levels (Yes = glyphosate-treated plot, No = control plot) 
	Phosphorus – two levels (Fertilised = P-fertilised subplot, Ambient = non-fertilised subplot)
        Height – plant height to the top of leaves (cm) at a given time point 	
        No.leaves - total number of leaves per plant
        No.damaged.leaves - number of damaged leaves per plant  
        Damage.intensity - two levels (0 = mild with < 50% of leaflets damaged, 1 = severe with 50% or more of leaflets damaged), 
                           note that only the plants that experienced herbivory were considered (i.e. No.damaged.leaves is >0)
        Time - three levels (late June, mid-July, late July)


Traits.xls
Resistance and performance traits of Lupinus polyphyllus based on a common garden experiment in 2020. Missing values are indicated by "n/a", and are due to deaths, lost samples, or zero nodule production.  
Variable list: 
	Plot – plot ID in the common garden (1-22)-
	Subplot – subplot ID (1-44)
	Pop - population ID (6 populations in total)
	Plant.ID - plant ID (1-264)
	Glyphosate – two levels (Yes = glyphosate-treated plot, No = control plot) 
	Phosphorus – two levels (Fertilised = P-fertilised subplot, Ambient = non-fertilised subplot)
	Initial.height – plant height to the top of leaves (cm) at the beginning of the experiment	
        Prop.dam.leaves - the proportion of damaged leaves (out of all leaves) in late July 
        No.trichomes - trichome number on the underside of the leaf (per cm2)
        LMA - leaf mass per unit area (mg cm2)
        Total.bm – plant total dry biomass in g
	Root.bm – root (belowground) dry biomass in g
        Shoot.bm – shoot (aboveground) dry biomass in g 
	Root.shoot.ratio - the proportion of root biomass of the total biomass
        No.nodules – number of nodules in the roots
	Red.nodules – number of red (active) nodules
	Nodules.dissected – number of nodules dissected
        
      
Herbivory.lab.xls
Leaf consumption by the land snail in Lupinus polyphyllus based on a laboratory feeding experiment in 2020.
Variable list: 
	Plot – plot ID in the common garden (1-22)
	Subplot – subplot ID (1-44)
	Pop - population ID (6 populations in total)
	Plant.ID - plant ID (1-264)
	Glyphosate – two levels (Yes = glyphosate-treated plot, No = control plot) 
	Phosphorus – two levels (Fertilised = P-fertilised subplot, Ambient = non-fertilised subplot)	
        Snail.size – snail shell width (mm)	
        Feeding.prob - feeding probability with two levels (1 = leaflet was damaged, 0 = leaflet was intact)
        LA.initial - initial leaf area (cm2) provided for the snail
        LA.consumed - leaf area consumed during the experiment (cm2), n/a denotes intact leaflets
      
