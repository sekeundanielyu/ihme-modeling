** Purpose: meta-analysis

import excel using "vitaA_diarrhea_rr.xlsx", firstrow clear

metan rr lower upper, random 

import excel using "vitaA_measles_rr.xlsx", firstrow clear

metan rr lower upper, random 
