'''
Command-line ready GBD Spectrum

Takes demographic and HIV-related inputs and produces
location-, year-, age-, and sex-specific (YAS) estimates of
HIV incidence, prevalence, and mortality.

External inputs (identified with input_folders_*i*.csv)
	1. Epidemic type (concentrated vs. generalized)
	2. Epidemic start year
	3. Region (not used)
	4. Migration (YAS counts)
	5. Baseline population (YAS counts)
	6. Age-specific fertility distribution (YA rates)
		- Normalized to sum to 1.0 on the fly
	7. Total fertility rate (Y rate)
	8. HIV-free mortality (YAS survival probabilities: 1-px)
	9. Sex ratio at birth (Y female births/male births)
	10. HIV mortality without ART (age/CD4 specific)
		- Rates of mortality due to HIV among PLWH not on treatment
	11. HIV mortality with ART
		- Varies by age, sex, CD4 at initiation, and duration on treatment
	12. Adult ART eligibility (Y threshold)
		- CD4 count below which all adults are eligible for ART
	13. HIV fertility ratio (A ratio)
		- Ratio of ASFR in HIV+ women to ASFR in HIV- women
	14. Adult ART coverage (YS count or percentage)
		- Percent or count of eligible adults receiving ART
	15. Progression between CD4 categories (age/CD4 specific rates)
	16. PMTCT coverage (year/treatment specific counts or percentages)
	17. 
'''

import csv, math, sys, logging, time, os, traceback, re, random
import numpy as np

code_path = os.path.dirname(os.path.realpath(__file__)) + '/'
sys.path.append(code_path)
import BeersInterpolation as beers

# Get settings directory and job ID
directory = sys.argv[2]
print directory
folder = directory[::-1][:directory[::-1].index('/')][::-1]
run_num = sys.argv[3]

# Read configurations from settings directory
config_path = directory + '/config.csv'
with open(config_path, 'r') as f:
	f_reader = csv.reader(f)
	config_data = [row for row in f_reader]
config = {row[0]: int(row[1]) for row in config_data if row[0] != 'prior_adj'}
config['prior_adj'] = [row for row in config_data if row[0] == 'prior_adj'][0][1]

with open(directory + '/iso_list.csv', 'r') as f:
	f_reader = csv.reader(f)
	iso_list = [row for row in f_reader]

ISO = sys.argv[1]

isoIndexInput = iso_list[0].index('iso3')
folderIndexInput = iso_list[0].index('input_folder')

input_folder_i = int([r[folderIndexInput] for r in iso_list if r[isoIndexInput] == ISO][0])

locationData = beers.openCSV(directory + "/input_folders_" + str(input_folder_i) + ".csv")

# Create data location object
locations = {k: v for [k,v] in locationData[1:]}

def flattenYearBySex(obj, year, sex, status = None, duration = None):
	'''	Takes population-like object, a year within
the range of the projection, and sex (which can
be "total" for the births object), and returns
those values for that sex in that year for each
individual age as a list.'''
	temp = []
	if not status and not duration:
		for i in obj:
			temp.append(obj[i][year][sex])
	elif status:
		for i in obj:
			temp.append(obj[i][year][sex][status])
		if duration:
			for i in obj:
				temp.append(obj[i][year][sex][status][duration])
	return temp

def totalByYear(obj, year, sex, status = None, duration = None):
	'''	Sums the list returned by flattenYearBySex
to give yearly, sex-specific totals.'''
	return np.sum(flattenYearBySex(obj, year, sex, status, duration))

def roundToTenth(a):
	return round(a * 10) / 10

def monthConcordance(age):
	if age == 0:
		return 0
	elif age in [1,2]:
		return 1
	elif age in [3,4]:
		return 2
	else:
		return 3

def normBounds(a, b):
	'''Get random variable from truncated normal distribution between a and b inclusive.'''
	val = 100
	while not(val >= a and val <= b):
		val = np.random.normal(0, 100)
	return val

def updateAllStateTotal(year):
	'''Update "all" category in population object.'''
	for age in population:
		for sex in sexes:
			population[age][year][sex]['all'] = 0.0
			if age > childMaxAge:
				for c in noARTCD4statesNeg:
					population[age][year][sex]['all'] += population[age][year][sex][c]
				for c in ARTCD4states:
					for d in population[age][year][sex][c]:
						population[age][year][sex]['all'] += population[age][year][sex][c][d]
			else:
				for h in childHIVstates[1:]:
					if h == 'neg':
						population[age][year][sex]['all'] += population[age][year][sex][h]
					else:
						for d in xrange(minDuration, age + 2):
							population[age][year][sex]['all'] += population[age][year][sex][h][d]


def getEligiblePregnantWomen(age, t):
	age5 = age - age % 5
	PW = 0
	age5index = (age - age % 5) / 5 - 3
	numEligible = 0
	numIneligible = 0
	for c in noARTCD4states:
		PW += population[age][t]['female'][c]
	PW = PW * TFR[t] * ASFRbyAge[age5][t-minYear]/np.sum(ASFRbyYear[t]) / 5 * TFRreduction[age5index]
	for c in noARTCD4states:
		if CD4lowerLimits[c] <= adultARTeligibility[t-minYear]:
			numEligible += population[age][t]['female'][c]
		else:
			numIneligible += population[age][t]['female'][c]
	if numEligible + numIneligible > 0:
		pregWomenNeed = PW * numEligible / (numEligible + numIneligible)
	else:
		pregWomenNeed = 0
	return pregWomenNeed

def getARTpatients(a1, a2, t, sex):
	tempSum = 0
	for age in xrange(a1, a2+1):
		if age > childMaxAge:
			for c in ARTCD4states:
				for d in adultARTdurations:
					tempSum += population[age][t][sex][c][d]
		else:
			for c in childHIVstates[2:]:
				for d in xrange(minDuration, age + 2):
					tempSum += population[age][t][sex][c][d]
	return tempSum

def calcBFtransmission(m1, m2, t):
	BFTR = 0
	percentOptA = treatPercent['optionA_BF']
	percentOptB = treatPercent['optionB_BF']

	dropoutOptA = postnatalDropout['optionA'][t-minYear]
	dropoutOptB = postnatalDropout['optionB'][t-minYear]

	optionATransRate = MTCtransRates['optionA']['BFGE350']
	optionBTransRate = MTCtransRates['optionB']['BFGE350']

	if propGE350 > 0:
		if (percentOptA + percentOptB - treatPercent['tripleARTbefPreg'] - treatPercent['tripleARTdurPreg']) > propGE350:
			excess = (percentOptA + percentOptB - treatPercent['tripleARTbefPreg'] - treatPercent['tripleARTdurPreg']) - propGE350
			optionATransRate = (propGE350 * MTCtransRates['optionA']['BFGE350'] + excess * 1.45 / 0.46 * MTCtransRates['optionA']['BFGE350']) / (propGE350 + excess)
			optionBTransRate = (propGE350 * MTCtransRates['optionB']['BFGE350'] + excess * 1.45 / 0.46 * MTCtransRates['optionB']['BFGE350']) / (propGE350 + excess)
	for d in xrange(m1, m2+1):
		percentOptA = treatPercent['optionA'] / (math.e ** (d * 2 * math.log(1 + dropoutOptA / 100)))
		percentOptB = treatPercent['optionB'] / (math.e ** (d * 2 * math.log(1 + dropoutOptB / 100)))
		percentNoProph = 1 - percentOptA - percentOptB - treatPercent['tripleARTbefPreg'] - treatPercent['tripleARTdurPreg']
		if percentNoProph < 0:
			percentNoProph = 0
		BFTR += (((1 - percentBFnoART[t-minYear][d] / 100) * (1 - percentInProgram)
			+ (1 - percentBFonART[t-minYear][d] / 100) * percentInProgram)
			* percentNoProph
			* (propLT350 * MTCtransRates['LT200']['BFLT350']
				+ propGE350 * MTCtransRates['GT350']['BFGE350']
				+ propIncidentInfections / 12 * MTCtransRates['IncidentInf']['BFLT350']))
		BFTR += (1 - percentBFonART[t-minYear][d] / 100) * percentOptA * optionATransRate
		BFTR += (1 - percentBFonART[t-minYear][d] / 100) * percentOptB * optionBTransRate

		if getARTpatients(15, maxAge, t, 'female') <= 0:
			propNewART = 0
		else:
			propNewART = (currentYearART['female'] - prevYearART['female']) / getARTpatients(15, maxAge, t, 'female')
		BFTR += ((1 - percentBFonART[t-minYear][d] / 100) * treatPercent['tripleARTbefPreg']
			* ((1 - propNewART) * MTCtransRates['tripleARTbefPreg']['BFLT350']
				+ propNewART * MTCtransRates['tripleARTdurPreg']['BFLT350']))
		BFTR += ((1 - percentBFonART[t-minYear][d] / 100) * treatPercent['tripleARTdurPreg']
			* (propNewART * MTCtransRates['tripleARTbefPreg']['BFLT350']
				+ (1 - propNewART) * MTCtransRates['tripleARTdurPreg']['BFLT350']))

	return BFTR * 2

def getBirths(t, sex = None):
	tempSum = 0
	for age in xrange(15, 50):
		if sex:
			tempSum += births[age][t][sex]
		else:
			tempSum += births[age][t]['total']
	return tempSum
	
col = lambda data, str: data[0].index(str)

writeFiles = True

# Get parent country (ISO) if needed
if ISO.find('_') != -1:
	regionCode = ISO
	ISO = ISO.split('_')[0]
else:
	regionCode = ISO

if ISO in ['MOZ', 'MDA', 'MYT']:
	for k in locations:
		if locations[k] == 'gbd_demproj':
			locations[k] = 'spectrum_demproj'

# Check if using alternate incidence directory
if len(sys.argv) > 7:
	if sys.argv[7] != 'none':
		locations['incidence'] = sys.argv[7]

# Check if using alternate output age groups
if len(sys.argv) > 8:
	output_type = sys.argv[8]
else:
	output_type = 'five_year'

# Check if using alternate adult ART coverage data
if len(sys.argv) > 9 and sys.argv[9] != 'none':
	locations['adultARTcoverage'] = sys.argv[9]

try:
	inputEpidemicTypeData = beers.openCSV('/strPath/epi_class.csv')
	epidemicType = [row[1] for row in inputEpidemicTypeData if row[0] == ISO][0]
except:
	epidemicType = 'CON'
if epidemicType == 'Custom':
	epidemicType = 'CON'

try:
	inputEpidemicStartYearData = beers.openCSV('/strPath/epi_start_year.csv')
	epidemicStartYear = [int(row[1]) for row in inputEpidemicStartYearData if row[0] == regionCode][0]
except:
	epidemicStartYear = 1984
if regionCode == 'ZAF':
	epidemicStartYear = 1986
	
demProjFilePath = "/strPath/"
AIMfilePath = demProjFilePath + 'AIM_assumptions/'

# Get list of country-specific seeds (for uncertainty)
seed_dir = '140825'
seed_loc = regionCode
seed_path = '%sseeds/%s/%s_seeds.csv' % (demProjFilePath, seed_dir, seed_loc)
with open(seed_path, 'r') as f:
	f_reader = csv.reader(f)
	seed_data = [row for row in f_reader]
run_i = seed_data[0].index('run')
seed_i = seed_data[0].index('seed')
seeds = {int(row[run_i]): int(float(row[seed_i])) for row in seed_data[1:]}

counterFactuals = ['ART']

# We need to adjust the sex ratio of incidence in order to get the sex ratio of
# deaths to line up with the ratio in the VR data.
try:
	inputSexRatioAdj = beers.openCSV(AIMfilePath + "/strPath/post_1995_sex_ratios.csv")
	
	isoIndex = inputSexRatioAdj[0].index('iso3')
	sexRatioVR = float([row for row in inputSexRatioAdj[1:] if row[isoIndex] == ISO][0][1])

	sexRatioAdj = sexRatioVR / .42
except:
	sexRatioAdj = 1

population = {}
migration = {}
deaths = {}
AIDSdeaths = {}
needForART = {}
minAge = 0
maxAge = 80

# Get first year of projection
if 'MOZ' not in ISO:
	minYear = 1970
else:
	minYear = 1982
if ISO == 'KHM':
	minYear = 1980			
if 'IND' in ISO:
	minYear = 1981
if 'MDA' in ISO:
	minYear = 1981			
if 'CHN' in ISO:
	minYear = 1980
if 'ZAF' in ISO:
	minYear = 1985
if ISO in ['TWN', 'PRK']:
	minYear = 1980

maxYear = 2015
sexes = ['male','female']
sex_nums = {'male': 1, 'female': 2}
noARTCD4states = ['LT50CD4', '50to99CD4', '100to199CD4', '200to249CD4',
'250to349CD4', '350to500CD4', 'GT500CD4']
# Create a copy of noARTCD4states with 'neg' included for interation convenience
noARTCD4statesNeg = ['neg', 'LT50CD4', '50to99CD4', '100to199CD4', '200to249CD4',
'250to349CD4', '350to500CD4', 'GT500CD4']
ARTCD4states = ['ARTLT50CD4', 'ART50to99CD4', 'ART100to199CD4', 'ART200to249CD4',
'ART250to349CD4', 'ART350to500CD4', 'ARTGT500CD4']
childHIVstates = ['all', 'neg', 'asym', 'asymBFLT6Mo', 'asymBF6to12Mo',
'asymBFGT12Mo', 'onFLART']
adultARTdurations = ['LT6Mo', '6to12Mo', 'GT12Mo']
PMTCTtreatmentOptions = ['singleDoseNevir', 'dualARV', 'optionA', 'optionB',
'tripleARTbefPreg', 'tripleARTdurPreg']
postnatalProphOptions = ['optionA', 'optionB']
allInterventions = ['ART', 'CTX', 'singleDoseNevir', 'dualARV', 'tripleARTdurPreg', 'tripleARTbefPreg','optionA', 'optionB', 'optionA_BF', 'optionB_BF']
minDuration = 1
maxAdultDuration = 30
maxChildDuration = 15
childMaxAge = 14

regionalEst = False

# Read in migration data
# (openCSV reads in row-by-row, all in string format)
new_loc = regionCode

try:
	inputMigrationData = beers.openCSV(demProjFilePath + locations['migration'] + "/migration/" + new_loc + "_migration.csv")
except:
	inputMigrationData = beers.openCSV(demProjFilePath + locations['migration'] + "/migration/" + "DEF" + "_migration.csv")
if regionCode == "IND":
	inputMigrationData = beers.openCSV(demProjFilePath + locations['migration'] + "/migration/" + "DEF" + "_migration.csv")

# Get locations of variables
# (Allows for varying variable positions)
yearIndexMig = inputMigrationData[0].index('year')
sexIndexMig = inputMigrationData[0].index('sex')
ageIndexMig = inputMigrationData[0].index('age')
valueIndexMig = inputMigrationData[0].index('value')

# Restrict data to year range
inputMigrationData = [[val for val in row] for row in inputMigrationData[1:] if int(row[yearIndexMig]) <= maxYear]

data_arr = np.array(inputMigrationData, dtype=float)

sorted_arr = data_arr[np.lexsort((data_arr[:,ageIndexMig], data_arr[:,sexIndexMig], data_arr[:, yearIndexMig]))]
inputMigrationData = [list(arr) for arr in sorted_arr]

# Read in population data
inputPopData = beers.openCSV(demProjFilePath + locations['population'] + "/pop/" + new_loc + "_pop.csv")

# Get locations of variables
yearIndexPop = inputPopData[0].index('year')
sexIndexPop = inputPopData[0].index('sex')
ageIndexPop = inputPopData[0].index('age')
valueIndexPop = inputPopData[0].index('value')

# Restrict to base year
inputPopData = [[val for val in row] for row in inputPopData[1:] if int(row[yearIndexPop]) == minYear]

# Read in total fertility rate (TFR) data
tmpRegionCode =  new_loc
if  new_loc == 'TWN':
	tmpRegionCode = 'TWN'
inputTFRdata = beers.openCSV(demProjFilePath + locations['TFR'] + "/tfr/" + tmpRegionCode + "_tfr.csv")

# Get variable locations
yearIndexTFR = inputTFRdata[0].index('year')
valueIndexTFR = inputTFRdata[0].index('value')

# Flatten array and restrict to year range
inputTFRdata = [[val for val in row] for row in inputTFRdata[1:] if int(row[yearIndexTFR]) <= maxYear]

data_arr = np.array(inputTFRdata, dtype=float)

sorted_arr = data_arr[data_arr[:, yearIndexTFR].argsort()]
inputTFRdata = [list(arr) for arr in sorted_arr]


# Read in age-specific fertility rate (ASFR) data
if locations['ASFR'] == 'gbd_demproj':
	tmpRegionCode = regionCode
	if regionCode == 'TWN':
		tmpRegionCode = 'TWN'
	inputASFRdata = beers.openCSV(demProjFilePath + locations['ASFR'] + "/asfr/" + tmpRegionCode + "_asfr.csv")
else:
	inputASFRdata = beers.openCSV(demProjFilePath + locations['ASFR'] + "/asfr/" + new_loc + "_asfr.csv")
# Get locations of variables
yearIndex = inputASFRdata[0].index('year')
ageIndex = inputASFRdata[0].index('age')
if 'IND_' not in regionCode:
	valueIndex = inputASFRdata[0].index('value')
else:
	valueIndex = inputASFRdata[0].index('v')	

# Restrict data to year range and five-year age groups
inputASFRdata = [[val for val in row] for row in inputASFRdata[1:] if int(row[yearIndex]) <= maxYear and int(row[ageIndex]) % 5 == 0]

# Multiply by the appropriate factor to get to five-year percentages
if 'spectrum_demproj' in locations['ASFR'] :
	# The default data need to be re-aggregated into five-year age groups
	factor = 500
else:
	# The GBD data do not need to be re-aggregated.
	factor = 100

# Create and fill ASFR objects
# "byYear" is only used for easy summation
ASFRbyAge = {}
for age in xrange(15, 50, 5):
	ASFRbyAge[age] = [float(row[valueIndex]) * factor for row in inputASFRdata if int(row[ageIndex]) == age]
ASFRbyYear = {}
for year in xrange(minYear, maxYear + 1):
	ASFRbyYear[year] = [float(row[valueIndex]) * factor for row in inputASFRdata if int(row[yearIndex]) == year]
 
# Read in survival rates

# Read in survival rates
loc_id = regionCode
if ('MDA' in regionCode) or ('MOZ' in regionCode) or ('KEN' in regionCode):
	loc_id = ISO
if ('IND' in regionCode) or ('ZAF' in regionCode):
	with open(demProjFilePath+"/iso3_loc_id_map.csv", 'r') as f:
		f_reader = csv.reader(f)
		isoMap = [row for row in f_reader]
	iso3IndexMap = isoMap[0].index('iso3')
	locIDindexMap = isoMap[0].index('ihme_loc_id')

	loc_id = [row[locIDindexMap] for row in isoMap if row[iso3IndexMap] == regionCode][0]

if locations['survivalRates'] != 'gbd_draws':
	inputSRdata = beers.openCSV(demProjFilePath + locations['survivalRates'] + "/life_tables/" + ISO + "_life_tables.csv")
else:
	inputSRdata = beers.openCSV('/ihme/gbd/WORK/02_mortality/03_models/5_lifetables/results/hivfree_sx/locs/' + loc_id + "_life_tables.csv")

yearIndexSurv = inputSRdata[0].index('year')
sexIndexSurv = inputSRdata[0].index('sex')
ageIndexSurv = inputSRdata[0].index('age')
if locations['survivalRates'] != 'gbd_draws':
	draw_col_surv = inputSRdata[0].index('Sx')

surv_vars = inputSRdata[0]

inputSRdata = [[val for val in row] for row in inputSRdata[1:] if int(row[yearIndexSurv]) <= maxYear]

for i in xrange(len(inputSRdata)):
	if int(inputSRdata[i][ageIndexSurv]) == 80 & int(inputSRdata[i-1][ageIndexSurv]) == 80:
		inputSRdata[i][ageIndexSurv] = 81

# Read in sex ratio at birth (SRB) data
tmpRegionCode = new_loc
if regionCode == 'TWN':
	tmpRegionCode = 'TWN'

inputSRBdata = beers.openCSV(demProjFilePath + locations['SRB'] + "/srb/" + tmpRegionCode + "_srb.csv")
# Get variable locations
yearIndexSRB = inputSRBdata[0].index('year')
valueIndexSRB = inputSRBdata[0].index('value')

# Flatten array and restrict data to year range.
inputSRBdata = [[val for val in row] for row in inputSRBdata[1:] if int(row[yearIndexSRB]) <= maxYear]

if 'paired' in locations['noARTmortality']:
	inputNoARTMortality = beers.openCSV(AIMfilePath + strPath + '/' + regionCode + "_mortality_par_draws.csv")
else:
	inputNoARTMortality = beers.openCSV(AIMfilePath + strPath + '/' + ISO + "_mortality_par_draws.csv")

if locations['onARTmortality'] == 'default_EPP_combo':
	inputOnARTMortality = beers.openCSV(AIMfilePath + strPath + "/" + ISO + "_HIVonART.csv")
elif 'paired' in locations['onARTmortality']:
	inputOnARTMortality = beers.openCSV(AIMfilePath + strPath + "/" + regionCode + "_HIVonART.csv")
else:
	inputOnARTMortality = beers.openCSV(AIMfilePath + strPath + "/" + ISO + "_HIVonART.csv")

print inputOnARTMortality[1][:10]

if 'paired' in locations['averageCD4duration']:
	inputProgressionParameters = beers.openCSV(AIMfilePath + strPath "/" + regionCode + "_progression_par_draws.csv")
else:
	inputProgressionParameters = beers.openCSV(AIMfilePath + strPath "/" + ISO + "_progression_par_draws.csv")

inputAdultARTeligibility = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + "_adult_eligible.csv")

if 'averages' in locations['TFRreduction']:
	inputTFRreduction = beers.openCSV(AIMfilePath + strPath + "/" + regionCode + "_TFR_ratio.csv")
else:
	inputTFRreduction = beers.openCSV(AIMfilePath + strPath + "/" + ISO + "_TFR_ratio.csv")

inputAdultARTCoverage = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + "_Adult_ART_cov.csv")

yearIndex = inputAdultARTCoverage[0].index('year')
sexIndex = inputAdultARTCoverage[0].index('sex')
numIndex = inputAdultARTCoverage[0].index('ART_cov_num')
pctIndex = inputAdultARTCoverage[0].index('ART_cov_pct')

data_arr = np.array(inputAdultARTCoverage[1:], dtype=float)
sorted_arr = data_arr[np.lexsort((data_arr[:,yearIndex], data_arr[:,sexIndex]))]

tmpAdultARTCoverage = [list(arr) for arr in sorted_arr]
tmpAdultARTCoverage.insert(0, inputAdultARTCoverage[0])

inputAdultARTCoverage = tmpAdultARTCoverage


inputPMTCT = beers.openCSV(AIMfilePath + 'program_stats/ART_pmtct/' + locations['PMTCT'] + '/' + new_loc + '_PMTCT_ART_cov.csv')
yearIndexPMTCT = inputPMTCT[0].index('year')

data_arr = np.array(inputPMTCT[1:], dtype=float)
sorted_arr = data_arr[data_arr[:,yearIndexPMTCT].argsort()]

tmpPMTCTcoverage = [list(arr) for arr in sorted_arr]
tmpPMTCTcoverage.insert(0, inputPMTCT[0])

inputPMTCT = tmpPMTCTcoverage

# Read in mean CD4 duration data
inputAverageCD4duration = beers.openCSV(AIMfilePath + "/strPath/DurationCD4cats.csv")

try:
	inputPostnatalDropout = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + '_PMTCT_mth_drop_rts.csv')
except:
	inputPostnatalDropout = beers.openCSV(AIMfilePath + strPath + '/' + "DEF" + '_PMTCT_mth_drop_rts.csv')
		
if locations['percentBF'] == 'defaults':
	inputPercentBF = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + '_notBF_pct.csv')
elif 'averages' in locations['percentBF']:
	inputPercentBF = beers.openCSV(AIMfilePath + strPath + '/' + regionCode + '_notBF_pct.csv')
	inputPercentBF[0] = [val.lower() for val in inputPercentBF[0]]
else:
	inputPercentBF = beers.openCSV(AIMfilePath + strPath + '/' + ISO + '_notBF_pct.csv')
	inputPercentBF[0] = [val.lower() for val in inputPercentBF[0]]

inputIncAgeDist = beers.openCSV(AIMfilePath + "strPath/GEN_IRR.csv")

# Get incidence and prevalence
inputEPPinc = beers.openCSV(demProjFilePath + strPath + '/' + regionCode + "_SPU_inc_draws.csv")
inputEPPprev = beers.openCSV(demProjFilePath + strPath + '/' + regionCode + "_SPU_prev_draws.csv")

# Get sex ratio of incidence (by epidemic type)
inputIncSexRatio = beers.openCSV(AIMfilePath + 'strPath/FtoM_inc_ratio_epidemic_specific.csv')

# Get CD4 distrubtion at infection
inputInitCD4dist = beers.openCSV(AIMfilePath + strPath + "/CD4count_distribution_at_infection.csv")

inputMTCtransRates= beers.openCSV(AIMfilePath + strPath + "/PMTCT_transmission_rts.csv")

inputChildCD4countDist = beers.openCSV(AIMfilePath + strPath + '/childCD4countDist.csv')

inputChildCD4percentDist = beers.openCSV(AIMfilePath + strPath + '/childCD4percentDist.csv')

inputChildARTelgibility = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + "_child_eligible.csv")

inputChildARTCoverage = beers.openCSV(AIMfilePath + strPath + '/' + new_loc + '_Child_ART_cov.csv')

inputChildHIVmortality = beers.openCSV(AIMfilePath + strPath + "/HIVtoAIDSdeath_children.csv")

inputChildCTXeffect = beers.openCSV(AIMfilePath + strPath + "/Child_treatment_effects_cotrim.csv")

inputEligiblePops = beers.openCSV(AIMfilePath + strPath + "/pops_eligible_regardless_cd4.csv")

# Get number of runs this job needs to do
indiv_run_nums = int(sys.argv[4])
# Check whether or not to adjust incidence to match prevalence
inc_adj_config = int(sys.argv[5])
# Get stage in whole process (pre- or post-incidence adjustment)
stage = sys.argv[6]

csvData = []
coverageData = []

# Start run loop
for run_id in xrange(indiv_run_nums):
	# Begin timing
	start_time = time.time()
	iteration_number = 0
	individual_id = (int(run_num) - 1) * indiv_run_nums + run_id + 1

	# Set both numpy and random module seeds
	np.random.seed(seeds[individual_id])
	random.seed(seeds[individual_id])
	adjustments = {}

	# Use previous adjustments if necessary
	if config['prior_adj'] != 'no':
		individual_id = prior_adj[individual_id]

	for counterfactual_type in counterFactuals:
		try:
	
			if counterfactual_type == 'no_ART':
				truth_val = True
			else:
				truth_val = False
			if counterfactual_type == 'HI':
				locations['onARTmortality'] = 'Mar2/DisMod_HI'
			elif counterfactual_type == 'HQ':
				locations['onARTmortality'] = 'Mar2/DisMod_BestSSA'
			
			# Set boolean for ART counterfactuals (true sets all treatment to 0)
			ARTcounterFactual = truth_val

			population = {}
			migration = {}
			deaths = {}
			AIDSdeaths = {}
			needForART = {}
			minAge = 0
			maxAge = 80

			# Get first year of projection
			if 'MOZ' not in ISO:
				minYear = 1970
			else:
				minYear = 1982
			if ISO == 'KHM':
				minYear = 1980			
			if 'IND' in ISO:
				minYear = 1981
			if 'MDA' in ISO:
				minYear = 1981			
			if 'CHN' in ISO:
				minYear = 1980
			if 'ZAF' in ISO:
				minYear = 1985
			if ISO in ['TWN', 'PRK']:
				minYear = 1980

			# maxYear = 2015
			sexes = ['male','female']
			sex_nums = {'male': 1, 'female': 2}
			noARTCD4states = ['LT50CD4', '50to99CD4', '100to199CD4', '200to249CD4',
			'250to349CD4', '350to500CD4', 'GT500CD4']
			# Create a copy of noARTCD4states with 'neg' included for interation convenience
			noARTCD4statesNeg = ['neg', 'LT50CD4', '50to99CD4', '100to199CD4', '200to249CD4',
			'250to349CD4', '350to500CD4', 'GT500CD4']
			ARTCD4states = ['ARTLT50CD4', 'ART50to99CD4', 'ART100to199CD4', 'ART200to249CD4',
			'ART250to349CD4', 'ART350to500CD4', 'ARTGT500CD4']
			childHIVstates = ['all', 'neg', 'asym', 'asymBFLT6Mo', 'asymBF6to12Mo',
			'asymBFGT12Mo', 'onFLART']
			adultARTdurations = ['LT6Mo', '6to12Mo', 'GT12Mo']
			PMTCTtreatmentOptions = ['singleDoseNevir', 'dualARV', 'optionA', 'optionB',
			'tripleARTbefPreg', 'tripleARTdurPreg']
			postnatalProphOptions = ['optionA', 'optionB']
			allInterventions = ['ART', 'CTX', 'singleDoseNevir', 'dualARV', 'tripleARTdurPreg', 'tripleARTbefPreg','optionA', 'optionB', 'optionA_BF', 'optionB_BF']
			minDuration = 1
			maxAdultDuration = 30
			maxChildDuration = 15
			childMaxAge = 14

			regionalEst = False

			mortalityAgeCategories = ["15-24", "25-34", "35-44", "45-54", "55-99"]

			possibleCD4categories = ['LT200', '200to350', '350to500', '500to750', '750to1000',
			'1000to1500', '1500to2000', '2000+']
			possibleCD4categoryCountValues = [200, 350, 500, 750, 1000, 1500, 2000, 10000]
			possibleCD4categoryPercentValues = [5, 10, 15, 20, 25, 30, 40, 100]
			possibleCD4categoryCounts = {}
			possibleCD4categoryPercents = {}
			for c in xrange(len(possibleCD4categories)):
				possibleCD4categoryCounts[possibleCD4categories[c]] = possibleCD4categoryCountValues[c]
				possibleCD4categoryPercents[possibleCD4categories[c]] = possibleCD4categoryPercentValues[c]

			# Set hardcoded values
			retentionRateCountValues = [0.986, 0.799, 0.761, 0.757, 0.666, 0.644, 0.460, 0.50]
			if iteration_number == 0:
				adj_array = [1 + (normBounds(-10,10)/100) for i in xrange(len(retentionRateCountValues))]
				adjustments['retentionRateCountValues'] = adj_array
			else:
				adj_array = adjustments['retentionRateCountValues']
			retentionRateCountValues = [retentionRateCountValues[i] * adj_array[i] for i in xrange(len(retentionRateCountValues))]		
			retentionRateCounts = {}

			retentionRatePercentValues = [0.906, 0.759, 0.787, 0.795, 0.785, 0.756, 0.813, 0.700]
			if iteration_number == 0:
				adj_array = [1 + (normBounds(-10,10)/100) for i in xrange(len(retentionRatePercentValues))]
				adjustments['retentionRatePercentValues'] = adj_array
			else:
				adj_array = adjustments['retentionRatePercentValues']
			retentionRatePercentValues = [retentionRatePercentValues[i] * adj_array[i] for i in xrange(len(retentionRatePercentValues))]
			retentionRatePercents = {}
			for i in xrange(len(possibleCD4categories)):
				retentionRateCounts[possibleCD4categories[i]] = retentionRateCountValues[i]
				retentionRatePercents[possibleCD4categories[i]] = retentionRatePercentValues[i]

			noART15CD4distValues = [0.056, 0.112, 0.112, 0.07, 0.14, 0.23, 0.28]
			if iteration_number == 0:
				adj_array = [1 + (normBounds(-10,10)/100) for i in xrange(len(noART15CD4distValues))]
				adjustments['noART15CD4distValues'] = adj_array
			else:
				adj_array = adjustments['noART15CD4distValues']
			tmpNoART15CD4distValues = [noART15CD4distValues[i] * adj_array[i] for i in xrange(len(noART15CD4distValues))]
			noART15CD4distValues = [val / np.sum(tmpNoART15CD4distValues) for val in tmpNoART15CD4distValues]
			noART15CD4dist = {}
			for i in xrange(len(noART15CD4distValues)):
				noART15CD4dist[noARTCD4states[-(i+1)]] = noART15CD4distValues[i]
			
			ART15CD4distValues = [0.11, 0.23, 0.23, 0.14, 0.29]
			if iteration_number == 0:
				adj_array = [1 + (normBounds(-10,10)/100) for i in xrange(len(noART15CD4distValues))]
				adjustments['ART15CD4distValues'] = adj_array
			else:
				adj_array = adjustments['ART15CD4distValues']
			tmpART15CD4distValues = [ART15CD4distValues[i] * adj_array[i] for i in xrange(len(ART15CD4distValues))]
			ART15CD4distValues = [val / np.sum(tmpART15CD4distValues) for val in tmpART15CD4distValues]
			ART15CD4dist = {}
			for i in xrange(len(ART15CD4distValues)):
				ART15CD4dist[ARTCD4states[-(i+3)]] = ART15CD4distValues[i]

			# All positive HIV states
			allCD4states = list(noARTCD4states)
			allCD4states.extend(ARTCD4states)

			# All HIV states excluding 'all'
			# (Useful for iteration)
			allCD4statesNeg = list(allCD4states)
			allCD4statesNeg.append('neg')

			if iteration_number == 0:
				adj = 1 + (normBounds(-10,10)/100)
				adjustments['childPrSurvivalFY'] = adj
			else:
				adj = adjustments['childPrSurvivalFY']
			childPrSurvivalFY = min(1, 0.85 * adj)

			if iteration_number == 0:
				adj = 1 + (normBounds(-10,10)/100)
				adjustments['childPrSurvivalSY'] = adj
			else:
				adj = adjustments['childPrSurvivalSY']
			childPrSurvivalSY = min(1, 0.93 * adj)

			# Initialize storage for population and death objects
			for obj in [population, deaths, AIDSdeaths, needForART]:
				for i in xrange(minAge, maxAge + 1):
					obj[i] = {}
					for j in xrange(minYear, maxYear + 1):
						obj[i][j] = {}
						for k in sexes:
							if obj == population:
								obj[i][j][k] = {}
								if i > childMaxAge:
									for l in noARTCD4statesNeg:
										obj[i][j][k][l] = 0.0
									for l in ARTCD4states:
										obj[i][j][k][l] = {}
										for d in adultARTdurations:
											obj[i][j][k][l][d] = 0.0

								else:
									for l in childHIVstates:
										if l in ['neg', 'all']:
											obj[i][j][k][l] = 0.0
										else:
											obj[i][j][k][l] = {}
											for d in xrange(minDuration, maxChildDuration + 1):
												obj[i][j][k][l][d] = 0.0
									obj[i][j][k]['needTx'] = {}
									for d in xrange(minDuration, maxChildDuration + 1):
										obj[i][j][k]['needTx'][d] = 0.0
							else:
								obj[i][j][k] = 0.0
			for age in xrange(minAge, childMaxAge + 1):
				for t in xrange(minYear, maxYear + 1):
					population[age][t]['both'] = {}
					population[age][t]['both']['needTx'] = {}
					population[age][t]['both']['needTx']['all'] = 0.0
					for d in xrange(minDuration, maxChildDuration + 1):
						population[age][t]['both']['needTx'][d] = 0.0
					for c in childHIVstates:
						if c in ['neg', 'all']:
							population[age][t]['both'][c] = 0.0
						else:
							population[age][t]['both'][c] = {}
							for d in xrange(minDuration, maxChildDuration + 1):
								population[age][t]['both'][c][d] = 0.0
							population[age][t]['both'][c]['all'] = 0.0

			AIDSdeathsCD4 = {}
			for age in xrange(0, 80, 5):
				AIDSdeathsCD4[age] = {}
				for t in xrange(minYear, maxYear+1):
					AIDSdeathsCD4[age][t] = {}
					for sex in sexes:
						AIDSdeathsCD4[age][t][sex] = {}
						if age >= 15:
							for c in allCD4states:
								if c in noARTCD4states:
									AIDSdeathsCD4[age][t][sex][c] = 0
								else:
									AIDSdeathsCD4[age][t][sex][c] = {}
									for d in adultARTdurations:
										AIDSdeathsCD4[age][t][sex][c][d] = 0
						else:
							AIDSdeathsCD4[age][t][sex]['onFLART'] = 0
							AIDSdeathsCD4[age][t][sex]['noART'] = 0


			AIDSdeathsCD4[80] = {}
			for t in xrange(minYear, maxYear+1):
				AIDSdeathsCD4[80][t] = {}
				for sex in sexes:
					AIDSdeathsCD4[80][t][sex] = {}
					for c in allCD4states:
						if c in noARTCD4states:
							AIDSdeathsCD4[80][t][sex][c] = 0
						else:
							AIDSdeathsCD4[80][t][sex][c] = {}
							for d in adultARTdurations:
								AIDSdeathsCD4[80][t][sex][c][d] = 0


			eligibleSpecialPops = {}
			for c in noARTCD4states:
				eligibleSpecialPops[c] = {}
				for sex in sexes:
					eligibleSpecialPops[c][sex] = 0

			######################
			## BASE  YEAR SETUP ##
			######################

			## Get single-year migration and migration rates

			# Get CSV with male migration data

			# Prepare migration object
			migration = {}
			for age in xrange(minAge, maxAge + 1):
				migration[age] = {}
				for t in xrange(minYear, maxYear + 1):
					migration[age][t] = {}

			if iteration_number == 0:
				adj_array = [1 + (normBounds(-10,10)/100) for row in inputMigrationData]
				adjustments['migration'] = adj_array
			else:
				adj_array = adjustments['migration']
			# Fill migration object, setting missing values to 0
			temp_i = 0
			if ISO not in ['IND', 'MDA']:
				for row in inputMigrationData:
					if int(row[yearIndexMig]) >= minYear and int(row[yearIndexMig]) <= maxYear:
						try:
							migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = float(row[valueIndexMig]) * adj_array[temp_i]
						except:
							migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = 0
						temp_i += 1
			else:
				for row in inputMigrationData:
					if int(row[yearIndexMig]) >= minYear and int(row[yearIndexMig]) <= maxYear:
						if int(row[ageIndexMig]) < 80:
							try:
								migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = float(row[valueIndexMig]) * adj_array[temp_i]
							except:
								migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = 0
							temp_i += 1
						elif int(row[ageIndexMig]) == 80:
							try:
								migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = float(row[valueIndexMig]) * adj_array[temp_i] * 5
							except:
								migration[int(row[ageIndexMig])][int(row[yearIndexMig])][sexes[int(row[sexIndexMig])-1]] = 0
							temp_i += 1

			# Fill population object, interpolating if non-single age data are detected
			if int(inputPopData[2][ageIndexPop]) != int(inputPopData[0][ageIndexPop]) + 2:
	
				if iteration_number == 0:
					adj_object = [{k: 1 + (normBounds(-10,10)/100) for k in sexes} for a in xrange(0,81)]
					adjustments['population'] = adj_object
				else:
					adj_object = adjustments['population']
	
				# Check if age 1 is included
				if int(inputPopData[1][ageIndexPop]) == 1:
					ageOne = True
				else:
					ageOne = False

				# Prepare containers to be used in interpolation
				# (Need a list for male and a list for females)
				popDataForInterpolation = {}
				interpolatedPopData = {}
				for sex in sexes:
					popDataForInterpolation[sex] = []

				# Reshape data into lists for interpolation
				for row in inputPopData:
					popDataForInterpolation[sexes[int(row[sexIndexPop])-1]].append(float(row[valueIndexPop]))

				# Combine age 0 with age 1, if necessary
				for sex in sexes:
					if ageOne:
						popDataForInterpolation[sex][0] += popDataForInterpolation[sex][1]
						popDataForInterpolation[sex].remove(popDataForInterpolation[sex][1])

				# Interpolate age groups 0 through 75, and append 80 at the end
				for sex in sexes:
					interpolatedPopData[sex] = beers.BeersInterpolateGroups(popDataForInterpolation[sex][:-1])
					interpolatedPopData[sex].append(popDataForInterpolation[sex][-1])

				# Fill population object with interpolated data
				for age in xrange(0, 81):
					for sex in sexes:
						population[age][minYear][sex]['neg'] = interpolatedPopData[sex][age] * adj_object[age][sex]

			# Fill object with single age input data, if interpolate isn't necessary 
			else:
				if iteration_number == 0:
					adj_array = [(1 + normBounds(-10,10)/100) for row in inputPopData]
					adjustments['population'] = adj_array
				else:
					adj_array = adjustments['population']

				temp_i = 0
				if ISO not in ['IND', 'MDA']:
					for row in inputPopData:
						try:
							population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = float(row[valueIndexPop]) * adj_array[temp_i]
						except:
							population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = 0
						temp_i += 1
				else:					
					for row in inputPopData:
						if int(row[ageIndexPop]) < 80:
							try:
								population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = float(row[valueIndexPop]) * adj_array[temp_i]
							except:
								population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = 0
							temp_i += 1
						elif int(row[ageIndexPop]) == 80:
							try:
								population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = float(row[valueIndexPop]) * adj_array[temp_i] * 5
							except:
								population[int(row[ageIndexPop])][int(row[yearIndexPop])][sexes[int(row[sexIndexPop])-1]]['neg'] = 0
							temp_i += 1
						else:
							pass

			if iteration_number == 0:
				adj_array = [(1 + normBounds(-10,10)/100) for row in inputTFRdata]
				adjustments['TFR'] = adj_array
			else:
				adj_array = adjustments['TFR']
			# Fill TFR object
			TFR = {}
			temp_i = 0
			for row in inputTFRdata:
				TFR[int(row[yearIndexTFR])] = float(row[valueIndexTFR]) * adj_array[temp_i]
				temp_i += 1


			if locations['survivalRates'] == 'gbd_draws':
				draw_list_surv = [val for val in surv_vars if 'px' in val]
				draw_num_list_surv = [int(re.findall('\d+', val)[0]) for val in draw_list_surv]
				n_surv_draws = len(draw_num_list_surv)

				draw_num_surv = draw_num_list_surv[(individual_id-1) % n_surv_draws]
				draw_col_surv = surv_vars.index('px' + str(draw_num_surv))
			survivalRates = {}
			for age in xrange(0, maxAge + 2):
				survivalRates[age] = {}
				for t in xrange(minYear, maxYear + 1):
					survivalRates[age][t] = {}



			for row in inputSRdata:
				if int(row[yearIndexSurv]) >= minYear and int(row[yearIndexSurv]) <= maxYear:
					if locations['survivalRates'] != 'gbd_draws':
						survivalRates[int(row[ageIndexSurv])][int(row[yearIndexSurv])][sexes[int(row[sexIndexSurv])-1]] = float(row[draw_col_surv])
					else:
						survivalRates[int(row[ageIndexSurv])][int(row[yearIndexSurv])][row[sexIndexSurv]] = float(row[draw_col_surv])

			last_sr_year = max([int(row[yearIndexSurv]) for row in inputSRdata])
			if maxYear > last_sr_year:
				needed_years = range(last_sr_year+1, maxYear+1)
				last_year_data = [row for row in inputSRdata if int(row[yearIndexSurv]) == last_sr_year]
				for y in needed_years:
					for row in last_year_data:
						if locations['survivalRates'] != 'gbd_draws':
							survivalRates[int(row[ageIndexSurv])][y][sexes[int(row[sexIndexSurv])-1]] = float(row[draw_col_surv])
						else:
							survivalRates[int(row[ageIndexSurv])][y][row[sexIndexSurv]] = float(row[draw_col_surv])



			updateAllStateTotal(minYear)

			# Fill SRB object by converting SRB to percent female
			SRB = {}
			if iteration_number == 0:
				adj_array = [(1 + normBounds(-10,10)/100) for row in inputSRBdata]
				adjustments['SRB'] = adj_array
			else:
				adj_array = adjustments['SRB']
			temp_i = 0
			for row in inputSRBdata:
				SRB[int(row[yearIndexSRB])] = 1 / ((float(row[valueIndexSRB]) * adj_array[temp_i]) / 100 + 1)
				temp_i += 1

			# Calculate base-year births
			births = {}
			for age in xrange(15, 50):
				# Get five-year age group for ASFR
				a5 = age - age % 5
				sr = survivalRates[age-1][minYear]['female']
				births[age] = {}
				births[age][minYear] = {}
				births[age][minYear]['total'] = (population[age][minYear]['female']['all'] + population[age - 1][minYear]['female']['all'] * sr) / 2 * TFR[minYear] * (ASFRbyAge[a5][minYear - minYear] / np.sum(ASFRbyYear[minYear]) / 5)
				births[age][minYear]['female'] = births[age][minYear]['total'] * SRB[minYear]
				births[age][minYear]['male'] = births[age][minYear]['total'] * (1 - SRB[minYear])


			# Calculate base-year deaths
			for age in deaths:
				for sex in sexes:
					sr = survivalRates[age][minYear][sex]
					# Ages 1 through maxAge - 1
					if age > 0 and age < max(population):
						mr = (migration[age-1][minYear][sex] + migration[age][minYear][sex]) / 2
						deaths[age][minYear][sex] = population[age-1][minYear][sex]['all'] * (1 - sr) + mr * (1 - sr) / 2
					# Age 80
					elif age == 80:
						mr = (migration[79][minYear][sex] + migration[80][minYear][sex]) / 2
						deaths[age][minYear][sex] = (population[79][minYear][sex]['all'] + population[80][minYear][sex]['all']) * (1 - sr) + mr * (1 - sr)/2
					# Age 0
					else:
						deaths[age][minYear][sex] = totalByYear(births, minYear, sex) * (1 - sr) + 0.5 * (1 - sr) / 2

			updateAllStateTotal(minYear)

			ageIndex = inputNoARTMortality[0].index('age')
			drawIndex = inputNoARTMortality[0].index('draw')
			CD4Index = inputNoARTMortality[0].index('cd4')
			try:
				valueIndex = inputNoARTMortality[0].index('mort')
			except:
				valueIndex = inputNoARTMortality[0].index('prog')

			tmpNoARTmortality = [row for row in inputNoARTMortality[1:] if int(row[drawIndex]) == ((individual_id-1) % 1000 + 1)]

			# CD4 category lower counts
			progressionAges = [15,25,35,45]
			noARTmortality = {}
			for sex in sexes:
				noARTmortality[sex] = []
				for i in xrange(len(progressionAges)):
					noARTmortality[sex].append({})
					for c in noARTCD4states:
						noARTmortality[sex][i][c] = 0.0

			for sex in sexes:
				for row in tmpNoARTmortality:
					a1 = int(row[ageIndex][:2])
					age10 = ((a1 - (a1 - 5) % 10) - 15) / 10
					noARTmortality[sex][age10][row[CD4Index]] = float(row[valueIndex])
					
					
			# HIV Mortality on ART
			if locations['onARTmortality'] == 'default_EPP_combo':
				durationIndex = inputOnARTMortality[0].index('durationart')
				CD4CatIndex = inputOnARTMortality[0].index('cd4_category')
				ageIndex = inputOnARTMortality[0].index('age')
				sexIndex = inputOnARTMortality[0].index('sex')
				valueIndex = inputOnARTMortality[0].index('mort')

				onARTmortality = {}
				for sex in sexes:
					onARTmortality[sex] = {}
					for d in adultARTdurations:
						onARTmortality[sex][d] = []
						for j in xrange(len(mortalityAgeCategories)):
							onARTmortality[sex][d].append({})
	
				if iteration_number == 0:
					adj_array = [(1 + normBounds(-10,10)/100) for row in inputOnARTMortality[1:]]
					adjustments['onARTmortality'] = adj_array
				else:
					adj_array = adjustments['onARTmortality']
				temp_i = 0
				for row in inputOnARTMortality[1:]:
					a1 = int(row[ageIndex][:2])
					age10 = ((a1 - (a1 - 5) % 10) - 15) / 10
					onARTmortality[sexes[int(row[sexIndex]) - 1]][row[durationIndex]][age10][row[CD4CatIndex]] = float(row[valueIndex]) * adj_array[temp_i]
					temp_i += 1
			else:
				durationIndex = inputOnARTMortality[0].index('durationart')
				CD4CatIndex = inputOnARTMortality[0].index('cd4_category')
				ageIndex = inputOnARTMortality[0].index('age')
				sexIndex = inputOnARTMortality[0].index('sex')

				draw_var_list = [val for val in inputOnARTMortality[0] if 'mort' in val]
				draw_num_list = [int(re.findall('\d+', val)[0]) for val in draw_var_list]
				max_draw_onartmort = max(draw_num_list)

				draw_num = (individual_id-1) % max_draw_onartmort + 1
				draw_col = inputOnARTMortality[0].index('mort' + str(draw_num))
				
				onARTmortality = {}
				for sex in sexes:
					onARTmortality[sex] = {}
					for d in adultARTdurations:
						onARTmortality[sex][d] = []
						for j in xrange(len(mortalityAgeCategories)):
							onARTmortality[sex][d].append({})

				for row in inputOnARTMortality[1:]:
					a1 = int(row[ageIndex][:2])
					age10 = ((a1 - (a1 - 5 ) % 10) - 15) / 10
					onARTmortality[sexes[int(row[sexIndex]) - 1]][row[durationIndex]][age10][row[CD4CatIndex]] = float(row[draw_col])

			ageIndex = inputProgressionParameters[0].index('age')
			drawIndex = inputProgressionParameters[0].index('draw')
			CD4Index = inputProgressionParameters[0].index('cd4')
			valueIndex = inputProgressionParameters[0].index('prog')

			tmpProgressionParameters = [row for row in inputProgressionParameters[1:] if int(row[drawIndex]) == ((individual_id-1) % 1000 + 1)]

			# CD4 category lower counts
			progressionAges = [15,25,35,45]
			progressionParameters = {}
			for age in progressionAges:
				progressionParameters[age] = {}
				for sex in sexes:
					progressionParameters[age][sex] = {}
					for c in noARTCD4states:
						progressionParameters[age][sex][c] = 0
						if c == 'LT50CD4':
							progressionParameters[age][sex][c] = 0.0000001
							
			for sex in sexes:
				for row in tmpProgressionParameters:
					a1 = int(row[ageIndex][:2])
					progressionParameters[a1][sex][row[CD4Index]] = float(row[valueIndex])

			yearIndex = inputAdultARTeligibility[0].index('year')
			valueIndex = inputAdultARTeligibility[0].index('cd4_threshold')

			adultARTeligibility = [float(row[valueIndex]) for row in inputAdultARTeligibility[1:] if int(row[yearIndex]) <= maxYear]

			# CD4 category lower counts
			CD4lowerLimitValues = [0,50,100,200,250,350,500]
			CD4lowerLimits = {}
			for i in xrange(len(noARTCD4states)):
				CD4lowerLimits[noARTCD4states[i]] = CD4lowerLimitValues[i]

			ageIndex = inputTFRreduction[0].index('age')
			valueIndex = inputTFRreduction[0].index('tfr_ratio')

			if iteration_number == 0:
				adj_array = [(1 + normBounds(-10,10)/100) for row in inputTFRreduction[1:]]
				adjustments['TFRreduction'] = adj_array
			else:
				adj_array = adjustments['TFRreduction']
			TFRreduction = [float(inputTFRreduction[1:][i][valueIndex]) * adj_array[i] for i in xrange(len(inputTFRreduction[1:]))]
			for i in xrange(len(TFRreduction)):
				if TFRreduction[i] == 0:
					TFRreduction[i] = 1.0

			yearIndex = inputAdultARTCoverage[0].index('year')
			sexIndex = inputAdultARTCoverage[0].index('sex')
			numIndex = inputAdultARTCoverage[0].index('ART_cov_num')
			pctIndex = inputAdultARTCoverage[0].index('ART_cov_pct')

			firstYear = int(inputAdultARTCoverage[1][yearIndex])
			lastYear = int(inputAdultARTCoverage[-1][yearIndex])

			coverageFillerData = [0 for i in xrange(minYear, firstYear)]

			adultARTCoverage = {}
			for sex in sexes:
				adultARTCoverage[sex] = list(coverageFillerData)
				adultARTCoverage[sex].extend([float(row[numIndex]) + float(row[pctIndex]) for row in inputAdultARTCoverage[1:] if sexes[int(row[sexIndex]) - 1] == sex])
			if firstYear < minYear:
				for sex in sexes:
					adultARTCoverage[sex] = adultARTCoverage[sex][minYear - firstYear:]
			print adultARTCoverage['male']
			
			if iteration_number == 0:
				adj_object = {k: (1 + normBounds(-10,10)/100) for k in adultARTCoverage}
				adjustments['adultARTCoverage'] = adj_object
			else:
				adj_object = adjustments['adultARTCoverage']
			
			for sex in adultARTCoverage:
				adj = adj_object[sex]
				for i in xrange(len(adultARTCoverage[sex])):
					adultARTCoverage[sex][i] = adultARTCoverage[sex][i] * adj

			inputMaleCoverage = [row for row in inputAdultARTCoverage[1:] if int(row[sexIndex]) == 1 and int(row[yearIndex]) >= minYear and int(row[yearIndex]) <= maxYear]
			print inputMaleCoverage
			adultARTCoverageType = ['num'] * len(inputMaleCoverage)
			for i in xrange(len(adultARTCoverageType)):
				if float(inputMaleCoverage[i][numIndex]) == 0 and float(inputMaleCoverage[i][pctIndex]) != 0:
					adultARTCoverageType[i] = 'percent'
			for i in xrange(len(adultARTCoverageType)):
				if adultARTCoverageType[i] == 'percent':
					for sex in sexes:
						adultARTCoverage[sex][i] = min(100, adultARTCoverage[sex][i])
			print adultARTCoverageType
			outputART = []
			for t in xrange(minYear, maxYear + 1):
				tempART = 0
				for sex in sexes:
					tempART += adultARTCoverage[sex][t-minYear]
				outputART.append(tempART)
			t = minYear

			if ARTcounterFactual:
				for sex in sexes:
					adultARTCoverage[sex] = [0 for i in xrange(len(adultARTCoverage[sex]))]

			# Get variable locations
			CD4CatIndex = inputAverageCD4duration[0].index('CD4_category')
			ageIndex = inputAverageCD4duration[0].index('age')
			sexIndex = inputAverageCD4duration[0].index('sex')
			valueIndex = inputAverageCD4duration[0].index('yearsCD4cat')

			# Create container with four age group-specific objects
			# (In most cases of ten-year age groups, data are stored
			# in lists, not dictionaries. 15-24 is the 0th item in
			# the list and so on)
			averageCD4Duration = []
			for i in xrange(4):
				averageCD4Duration.append({})
		
			if iteration_number == 0:
				adj_array = [(1 + normBounds(-10,10)/100) for row in inputAverageCD4duration[1:]]
				adjustments['averageCD4Duration'] = adj_array
			else:
				adj_array = adjustments['averageCD4Duration']

			# Fill mean duration object
			temp_i = 0
			for row in inputAverageCD4duration[1:]:
				a1 = int(row[ageIndex][:2])
				age10 = ((a1 - (a1 - 5) % 10) - 15) / 10
				averageCD4Duration[age10][row[CD4CatIndex]] = float(row[valueIndex]) * adj_array[temp_i]
				temp_i += 1

			tempPMTCT = {}
			treatTypes = np.unique([var[:-4] for var in inputPMTCT[0] if var != 'year'])

			yearIndex = inputPMTCT[0].index('year')
			startYear = min([int(row[yearIndex]) for row in inputPMTCT[1:]])

			tempPMTCT = {}
			percent_val_list = []
			treat_data_type = {}
			for p in treatTypes:
				treat_data_type[p] = []
				filler = [0 for i in xrange(minYear, startYear)]
				col_nums = [i for i in xrange(len(inputPMTCT[0])) if p in inputPMTCT[0][i]]
				pct_col = [i for i in xrange(len(inputPMTCT[0])) if inputPMTCT[0][i] == p+'_pct'][0]
				num_col = [i for i in xrange(len(inputPMTCT[0])) if inputPMTCT[0][i] == p+'_num'][0]
				if not ARTcounterFactual:
					tmp_num = np.array([float(row[num_col]) for row in inputPMTCT[1:]])
					tmp_pct = np.array([float(row[pct_col]) for row in inputPMTCT[1:]])
				else:
					tmp_num = np.array([float(0) for row in inputPMTCT[1:]])
					tmp_pct = np.array([float(0) for row in inputPMTCT[1:]])

				percent_val_list.append(tmp_pct)
				for t in xrange(len(tmp_pct)):
					if tmp_num[t] != 0 and tmp_pct[t] == 0:
						treat_data_type[p].append('num')
					elif tmp_num[t] == 0 and tmp_pct[t] != 0:
						treat_data_type[p].append('percent')
					elif tmp_num[t] == 0 and tmp_pct[t] == 0:
						treat_data_type[p].append('num')
					elif tmp_num[t] != 0 and tmp_pct[t] != 0:
						treat_data_type[p].append('num')
						tmp_pct[t] = 0
				total = tmp_pct + tmp_num
				filler.extend(total)
				tmp_cov = list(filler)
				tempPMTCT[p] = tmp_cov
			PMTCTtype = {}
			PMTCTtype['prenat'] = {}
			PMTCTtype['postnat'] = {}
			for p in treat_data_type:
				filler = ['num' for i in xrange(minYear, startYear)]
				filler.extend(treat_data_type[p])
				if 'postnat' in p:
					PMTCTtype['postnat'][p.split('_')[-1]] = filler
				else:
					PMTCTtype['prenat'][p.split('_')[-1]] = filler

			prenatalProph = {}
			postnatalProph = {}
			for key in tempPMTCT:
				if 'postnat' in key:
					postnatalProph[key.split('_')[1]] = tempPMTCT[key]
				elif 'prenat' in key:
					prenatalProph[key.split('_')[1]] =  tempPMTCT[key]
				else:
					prenatalProph[key] = tempPMTCT[key]

			if iteration_number == 0:
				adj_object = {k: (1 + normBounds(-10,10)/100) for k in prenatalProph}
				adjustments['prenatalProph'] = adj_object
			else:
				adj_object = adjustments['prenatalProph']

			for treatType in prenatalProph:
				adj = adj_object[treatType]
				for y in xrange(len(prenatalProph[treatType])):
					prenatalProph[treatType][y] = prenatalProph[treatType][y] * adj
				
			if iteration_number == 0:
				adj_object = {k: (1 + normBounds(-10,10)/100) for k in postnatalProph}
				adjustments['postnatalProph'] = adj_object
			else:
				adj_object = adjustments['postnatalProph']
			for treatType in postnatalProph:
				adj = adj_object[treatType]
				for y in xrange(len(postnatalProph[treatType])):
					postnatalProph[treatType][y] = postnatalProph[treatType][y] * adj
			
			for p in prenatalProph:
				for y in xrange(len(prenatalProph[p])):
					if PMTCTtype['prenat'][p][y] == 'percent':
						prenatalProph[p][y] = min(100.0, prenatalProph[p][y])
			for p in postnatalProph:
				for y in xrange(len(postnatalProph[p])):
					if PMTCTtype['postnat'][p][y] == 'percent':
						postnatalProph[p][y] = min(100.0, postnatalProph[p][y])
				
			tmpPostnatalDropout = {}

			if iteration_number == 0:
				adj_object = {k: (1 + normBounds(-10,10)/100) for k in [j for j in inputPostnatalDropout[0] if j != 'year']}
				adjustments['postnatalDropout'] = adj_object
			else:
				adj_object = adjustments['postnatalDropout']
			for key in [k for k in inputPostnatalDropout[0] if k != 'year']:
				adj = adj_object[key]
				tmpPostnatalDropout[key.split('_')[-1]] = [float(row[inputPostnatalDropout[0].index(key)]) * adj for row in inputPostnatalDropout[1:]]

			dataStartYear = int(inputPostnatalDropout[1][0])
			postnatalDropout = {}
			for k in tmpPostnatalDropout:
				postnatalDropout[k] = [tmpPostnatalDropout[k][0]] * (dataStartYear - minYear)
				postnatalDropout[k].extend(tmpPostnatalDropout[k])

			if locations['percentBF'] == 'defaults':
				valueIndex = inputPercentBF[0].index('notBF_pct')

				tempPercentBFvalues = [float(row[valueIndex]) for row in inputPercentBF[1:]]

				if iteration_number == 0:
					adj_array = [1 + normBounds(-10,10)/100 for i in xrange(len(tempPercentBFvalues))]
					adjustments['percentBFonART'] = adj_array
				else:
					adj_array = adjustments['percentBFonART']

				testPercentBF = {i+1: min(100, val * adj_array[i]) for i, val in zip(xrange(len(tempPercentBFvalues)), tempPercentBFvalues)}
				percentBFonART = [testPercentBF for i in xrange(minYear, maxYear+1)]
				percentBFnoART = [testPercentBF for i in xrange(minYear, maxYear+1)]

			else:
				noARVindex = inputPercentBF[0].index('no_arv')
				onARVindex = inputPercentBF[0].index('on_arv')
				
				tmpNoARV = [float(row[noARVindex]) for row in inputPercentBF[1:]]
				tmpOnARV = [float(row[onARVindex]) for row in inputPercentBF[1:]]

				if iteration_number == 0:
					adj_array = [1 + normBounds(-10,10)/100 for i in xrange(len(tmpNoARV))]
					adjustments['percentBFnoART'] = adj_array
				else:
					adj_array = adjustments['percentBFnoART']
				percentBFnoARTvalues = {i+1: min(100, val * adj_array[i]) for i, val in zip(xrange(len(tmpNoARV)), tmpNoARV)}
				
				if iteration_number == 0:
					adj_array = [1 + normBounds(-10,10)/100 for i in xrange(len(tmpOnARV))]
					adjustments['percentBFonART'] = adj_array
				else:
					adj_array = adjustments['percentBFonART']				
				percentBFonARTvalues = {i+1: min(100, val * adj_array[i]) for i, val in zip(xrange(len(tmpOnARV)), tmpOnARV)}
				percentBFonART = [percentBFonARTvalues for i in xrange(minYear, maxYear+1)]
				percentBFnoART = [percentBFnoARTvalues for i in xrange(minYear, maxYear+1)]


			# Create HIV-specific data containers
			eligibleAdults = []
			for i in xrange(minYear, maxYear+1):
				eligibleAdults.append({})
				for sex in sexes:
					eligibleAdults[i-minYear][sex] = 0
			eligibleAdultsCD4 = {}
			for i in xrange(len(noARTCD4states)):
				eligibleAdultsCD4[noARTCD4states[i]] = {}
				for sex in sexes:
					eligibleAdultsCD4[noARTCD4states[i]][sex] = 0

			currentYearART = {}
			prevYearART = {}
			twoPrevYearsART = {}
			for obj in [currentYearART, prevYearART, twoPrevYearsART]:
				for sex in sexes:
					obj[sex] = 0 

			# Number of increments in a year
			timeStep = 10

			eligByAge = []
			for i in xrange(4):
				eligByAge.append({})
				for c in xrange(len(noARTCD4states)):
					eligByAge[i][noARTCD4states[c]] = {}
					for sex in sexes:
						eligByAge[i][noARTCD4states[c]][sex] = 0

			mortRate = {}
			for c in noARTCD4states:
				mortRate[c] = 0

			newPatients = {}
			for c in noARTCD4states:
				newPatients[c] = {}
				for sex in sexes:
					newPatients[c][sex] = 0

			entrants = {}
			exits = {}
			for obj in [entrants, exits]:
				for c in allCD4states:
					obj[c] = {}
					if c in noARTCD4states:
						obj[c][1] = 0
					else:
						for d in adultARTdurations:
							obj[c][d] = 0

			# Use generalized age pattern of incidence
			# Create age distribution object
			ageIndex = inputIncAgeDist[0].index('age')
			sexIndex = inputIncAgeDist[0].index('sex')
			upperIndex = inputIncAgeDist[0].index('upper')
			lowerIndex = inputIncAgeDist[0].index('lower')

			tmp_incAgeDist_SY = {}
			incAgeDist_SY = {}
			for sex in sexes:
				tmp_incAgeDist_SY[sex] = {}
				incAgeDist_SY[sex] = {}
				for age in xrange(0, maxAge + 1, 5):
					tmp_incAgeDist_SY[sex][age] = 0
					incAgeDist_SY[sex][age] = 0

			for row in inputIncAgeDist[1:]:
				a1 = int(row[ageIndex][:2])
				tmp_incAgeDist_SY[sexes[int(row[sexIndex]) - 1]][a1] = random.uniform(float(row[lowerIndex]), float(row[upperIndex]))

			for sex in sexes:
				tmp25 = tmp_incAgeDist_SY[sex][25]
				for age in tmp_incAgeDist_SY[sex]:
					incAgeDist_SY[sex][age] = tmp_incAgeDist_SY[sex][age] / tmp25

			incAgeDist = {}
			for sex in sexes:
				incAgeDist[sex] = []
				for t in xrange(minYear, maxYear + 1):
					incAgeDist[sex].append({})
					for age in xrange(0, maxAge + 1, 5):
						incAgeDist[sex][t-minYear][age] = incAgeDist_SY[sex][age]

			variables_inc = inputEPPinc[0]
			draw_list_inc = [val for val in variables_inc if 'draw' in val]
			draw_num_list_inc = [int(re.findall('\d+', val)[0]) for val in draw_list_inc]
			max_draw_inc = max(draw_num_list_inc)
			
			draw_num_inc = (individual_id-1) % max_draw_inc + 1
			draw_col_inc = variables_inc.index('draw' + str(draw_num_inc))
		
			variables_prev = inputEPPprev[0]
			draw_list_prev = [val for val in variables_prev if 'draw' in val]
			draw_num_list_prev = [int(re.findall('\d+', val)[0]) for val in draw_list_prev]
			max_draw_prev = max(draw_num_list_prev)

			draw_num_prev = (individual_id-1) % max_draw_prev + 1
			draw_col_prev = variables_prev.index('draw' + str(draw_num_prev))

			prev_data = [float(row[draw_col_prev]) for row in inputEPPprev[1:]]
			inc_data = [float(row[draw_col_inc]) for row in inputEPPinc[1:]]
			yearIndex = variables_inc.index('year')
			years = [int(row[yearIndex]) for row in inputEPPinc[1:]]

			EPPdata = {row[0]: {'inc': row[1], 'prev': row[2]} for row in zip(years, inc_data, prev_data)}

			incSexRatioData = [row for row in inputIncSexRatio[1:] if row[1] == epidemicType]

			yearIndex = inputIncSexRatio[0].index('year')
			valueIndex = inputIncSexRatio[0].index('FtoM_inc_ratio')

			# Set initial values
			incSexRatio = [.24 * sexRatioAdj for i in xrange(minYear, maxYear + 1)]

			if iteration_number == 0:
				adj = 1 + normBounds(-20,20)/100
				adjustments['incSexRatio'] = adj
			else:
				adj = adjustments['incSexRatio']

			# Replace inital values with actual values
			for y in xrange(epidemicStartYear, maxYear + 1):
				incSexRatio[y-minYear] = float(incSexRatioData[min(y-epidemicStartYear, len(incSexRatioData)-1)][valueIndex]) * adj * sexRatioAdj
			
			CD4CatIndex = inputInitCD4dist[0].index('CD4_category')
			ageIndex = inputInitCD4dist[0].index('age')
			valueIndex = inputInitCD4dist[0].index('Pct_new_infections')
			sexIndex = inputInitCD4dist[0].index('sex')

			sexes = ['male', 'female']
			noARTCD4states = ['LT50CD4', '50to99CD4', '100to199CD4', '200to249CD4',
				'250to349CD4', '350to500CD4', 'GT500CD4']

			initCD4dist = []
			for i in xrange(4):
				initCD4dist.append({})
				for c in noARTCD4states:
					initCD4dist[i][c] = {}


			for row in inputInitCD4dist[1:]:
				a1 = int(row[ageIndex][:2])
				age10 = ((a1 - (a1 - 5) % 10) - 15) / 10
				initCD4dist[age10][row[CD4CatIndex]][sexes[int(row[sexIndex])-1]] = float(row[valueIndex])

			if iteration_number == 0:
				adj_array = [1 + normBounds(-10,10)/100 for a in xrange(len(initCD4dist))]
				adjustments['initCD4dist'] = adj_array
			else:
				adj_array = adjustments['initCD4dist']
			for s in sexes:
				for a in xrange(len(initCD4dist)):
					initCD4dist[a]['GT500CD4'][s] = initCD4dist[a]['GT500CD4'][s] * adj_array[a]
					initCD4dist[a]['350to500CD4'][s] = 100 - initCD4dist[a]['GT500CD4'][s]

			MTCtransRates = {}
			transTypes = ['LT200', '200to350', 'GT350', 'IncidentInf', 'singleDoseNevir', 'dualARV', 'optionA', 'optionB', 'tripleARTbefPreg', 'tripleARTdurPreg']

			if iteration_number == 0:
				adj_object = [{k: 1 + normBounds(-10,10)/100 for k in ['perinatal', 'BFLT350', 'BFGE350']} for i in xrange(len(inputMTCtransRates[1:]))]
				adjustments['MTCtransRates'] = adj_object
			else:
				adj_object = adjustments['MTCtransRates']

			for i in xrange(len(inputMTCtransRates[1:])):
				MTCtransRates[transTypes[i]] = {}
				for inf in ['perinatal', 'BFLT350', 'BFGT350']:
					typeIndex = [inputMTCtransRates[0].index(val) for val in inputMTCtransRates[0] if inf.lower()[2:] in val][0]
					infname = inf
					if inf == 'BFGT350':
						infname = 'BFGE350'
					try:
						MTCtransRates[transTypes[i]][infname] = float(inputMTCtransRates[1:][i][typeIndex]) / 100 * adj_object[i][infname]
					except:
						MTCtransRates[transTypes[i]][infname] = inputMTCtransRates[1:][i][typeIndex]

			childCD4countDist = {}
			for i in xrange(minYear + 1, maxYear + 1):
				childCD4countDist[i] = []
			for j in xrange(len(childCD4countDist)):
				for i in xrange(len(inputChildCD4countDist)):
					childCD4countDist[j + minYear + 1].append({})
					for c in xrange(len(inputChildCD4countDist[i][1:])):
						if j == 0:
							childCD4countDist[j + minYear + 1][i][possibleCD4categories[c]] = float(inputChildCD4countDist[i][1:][c])
						else:
							childCD4countDist[j + minYear + 1][i][possibleCD4categories[c]] = 0.0

			if iteration_number == 0:
				adj_object = [{k: 1 + normBounds(-10,10)/100 for k in childCD4countDist[minYear+1][a]} for a in xrange(len(childCD4countDist[minYear+1]))]
				adjustments['childCD4countDist'] = adj_object
			else:
				adj_object = adjustments['childCD4countDist']

			for a in xrange(len(childCD4countDist[minYear+1])):
				tmpDist = {}
				for c in childCD4countDist[minYear+1][a]:
					tmpDist[c] = childCD4countDist[minYear+1][a][c] * adj_object[a][c]
				for c in childCD4countDist[minYear+1][a]:
					childCD4countDist[minYear+1][a][c] = tmpDist[c] / sum(tmpDist.values()) * 100

			childCD4percentDist = {}
			for i in xrange(minYear + 1, maxYear + 1):
				childCD4percentDist[i] = []
			for j in xrange(len(childCD4percentDist)):
				for i in xrange(len(inputChildCD4percentDist)):
					childCD4percentDist[j + minYear + 1].append({})
					for c in xrange(len(inputChildCD4percentDist[i][1:])):
						if j == 0:
							childCD4percentDist[j + minYear + 1][i][possibleCD4categories[c]] = float(inputChildCD4percentDist[i][1:][c])
						else:
							childCD4percentDist[j + minYear + 1][i][possibleCD4categories[c]] = 0.0

			if iteration_number == 0:
				adj_object = [{k: 1 + normBounds(-10,10)/100 for k in childCD4percentDist[minYear+1][a]} for a in xrange(len(childCD4percentDist[minYear+1]))]
				adjustments['childCD4percentDist'] = adj_object
			else:
				adj_object = adjustments['childCD4percentDist']

			for a in xrange(len(childCD4percentDist[minYear+1])):
				tmpDist = {}
				for c in childCD4percentDist[minYear+1][a]:
					tmpDist[c] = childCD4percentDist[minYear+1][a][c] * adj_object[a][c]
				for c in childCD4percentDist[minYear+1][a]:
					childCD4percentDist[minYear+1][a][c] = tmpDist[c] / sum(tmpDist.values()) * 100

			ageThresholdIndex = inputChildARTelgibility[0].index('age_below_all_treat_mos')
			countThresholdIndex = inputChildARTelgibility[0].index('cd4_count_thresh')
			percentThresholdIndex = inputChildARTelgibility[0].index('cd4_pct_thresh')
			ageIndex = inputChildARTelgibility[0].index('age')
			yearIndex = inputChildARTelgibility[0].index('year')

			childEligibilityAge = [float(row[ageThresholdIndex]) for row in inputChildARTelgibility[1:] if row[ageIndex] == '12to35mos']

			orderedAges = ['LT11mos', '12to35mos', '35to59mos', 'GT5yrs']

			childEligibilityCount = []
			childEligibilityPercent = []
			for i in xrange(len(orderedAges)):
				childEligibilityCount.append([float(row[countThresholdIndex]) for row in inputChildARTelgibility[1:] if row[ageIndex] == orderedAges[i]])
				childEligibilityPercent.append([float(row[percentThresholdIndex]) for row in inputChildARTelgibility[1:] if row[ageIndex] == orderedAges[i]])

			yearIndex = inputChildARTCoverage[0].index('year')
			ARTnumIndex = inputChildARTCoverage[0].index('ART_cov_num')
			CTXnumIndex = inputChildARTCoverage[0].index('Cotrim_cov_num')
			ARTpctIndex = inputChildARTCoverage[0].index('ART_cov_pct')
			CTXpctIndex = inputChildARTCoverage[0].index('Cotrim_cov_pct')

			firstYear = int(inputChildARTCoverage[1][yearIndex])

			coverageFillerData = [0 for i in xrange(minYear, firstYear)]
			
			if iteration_number == 0:
				adj_object = {p: [1 + normBounds(-10,10)/100 for i in inputChildARTCoverage[1:]] for p in ['num', 'pct']}
				adjustments['childARTcoverageCTX'] = adj_object
			else:
				adj_object = adjustments['childARTcoverageCTX']

			childARTcoverage = {}
			childARTcoverage['CTX'] = list(coverageFillerData)
			childARTcoverage['CTX'].extend([float(inputChildARTCoverage[1:][i][CTXnumIndex]) * adj_object['num'][i] + min(100,float(inputChildARTCoverage[1:][i][CTXpctIndex]) * adj_object['pct'][i]) for i in xrange(len(inputChildARTCoverage[1:]))])
			
			if iteration_number == 0:
				adj_object = {p: [1 + normBounds(-10,10)/100 for i in inputChildARTCoverage[1:]] for p in ['num', 'pct']}
				adjustments['childARTcoverageART'] = adj_object
			else:
				adj_object = adjustments['childARTcoverageART']			
			childARTcoverage['ART'] = list(coverageFillerData)
			childARTcoverage['ART'].extend([float(inputChildARTCoverage[1:][i][ARTnumIndex]) * adj_object['num'][i] + min(100,float(inputChildARTCoverage[1:][i][ARTpctIndex]) * adj_object['pct'][i]) for i in xrange(len(inputChildARTCoverage[1:]))])

			if ARTcounterFactual:
				for l in childARTcoverage:
					childARTcoverage[l] = [0 for x in xrange(len(childARTcoverage[l]))]

			childARTcoverageType = {}
			for i in ['CTX', 'ART']:
				childARTcoverageType[i] = ['num' for x in xrange(minYear, firstYear)]

			childARTcoverageType['CTX'].extend(['percent' if float(row[CTXpctIndex]) > 0 else 'num' for row in inputChildARTCoverage[1:]])
			childARTcoverageType['ART'].extend(['percent' if float(row[ARTpctIndex]) > 0 else 'num' for row in inputChildARTCoverage[1:]])

			childInfectionCategories = ['perinatal', 'postnatal0to180', 'postnatal181to365', 'postnatal365+']
			valueIndices = {}
			childHIVmortality = {}
			for infType in childInfectionCategories:
				if infType != 'postnatal365+':
					valueIndices[infType] = inputChildHIVmortality[0].index(infType)
					childHIVmortality[infType] = [float(row[valueIndices[infType]]) for row in inputChildHIVmortality[1:]]
				else:
					valueIndices[infType] = inputChildHIVmortality[0].index('postnatal365plus')
					childHIVmortality[infType] = [float(row[valueIndices[infType]]) for row in inputChildHIVmortality[1:]]

			yearIndex = inputChildCTXeffect[0].index('year_fm_start')
			statusIndex = inputChildCTXeffect[0].index('ART_status')
			valueIndex = inputChildCTXeffect[0].index('hivmort_reduction')

			childCTXeffect = {}
			childCTXeffect['noART'] = []
			childCTXeffect['onART'] = []
	
			for row in inputChildCTXeffect[1:]:
				if row[statusIndex] == 'noART':
					childCTXeffect['noART'].append(float(row[valueIndex]))
				else:
					childCTXeffect['onART'].append(float(row[valueIndex]))

			if iteration_number == 0:
				adj_object = {k: [1 + (normBounds(-10,10)/100) for i in childCTXeffect[k]] for k in childCTXeffect}
				adjustments['childCTXeffect'] = adj_object
			else:
				adj_object = adjustments['childCTXeffect']

			for k in childCTXeffect:
				for a in xrange(len(childCTXeffect[k])):
					childCTXeffect[k][a] = childCTXeffect[k][a] * adj_object[k][a]

			eligiblePopsData = [row for row in inputEligiblePops if row[col(inputEligiblePops, 'iso3')] == regionCode]

			eligiblePopTuples = [(row[col(inputEligiblePops, 'pop_eligible')], row[col(inputEligiblePops, 'year_implemented')], row[col(inputEligiblePops, 'estimated_pct_HIVpos')]) for row in eligiblePopsData if row[col(inputEligiblePops, 'eligible')] == 'Y']
			eligiblePops = [tup[0] for tup in eligiblePopTuples]
			eligiblePopYears = {k: int(v) for (k,v,y) in eligiblePopTuples}
			eligiblePopPercents = {k: float(v) / 100 for (k,y,v) in eligiblePopTuples if k != "pregnant_women"}

			need15plus = {}
			for year in xrange(minYear, maxYear+1):
				need15plus[year] = {}
				for sex in sexes:
					need15plus[year][sex] = 0
			t = minYear

			# Write initial data to csvData list
			out_cats = ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']

			tmpPop = {}
			if output_type == 'five_year':
				for sex in sexes:
					for age in xrange(0, 15, 5):
						popData = []
						tmpNewHIV = 0
						tmpDeaths = 0
						tmpHIVbirths = 0
						tmpTotalBirths = 0
						tmpNonAIDSdeaths = 0
						HivDARTData = []
						tmpHivDART = {}
						HivDnoARTData = []
						tmpHivDnoART = {}
						PonARTData = []
						tmpPonART = {}
						PnoARTData = []
						tmpPnoART = {}
						for a in ARTCD4states:
							tmpHivDART[a] = 0
							HivDARTData.append(tmpHivDART[a])
						for b in noARTCD4states:
							tmpHivDnoART[b] = 0
							HivDnoARTData.append(tmpHivDnoART[b])
						for a5 in xrange(age, age + 5):
							tmpNonAIDSdeaths += deaths[a5][t][sex]
						for c in ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']:
							tmpPop[c] = 0
							for a5 in xrange(age, age + 5):
								if c == 'neg':
									tmpPop[c] += population[a5][t][sex][c]
							popData.append(tmpPop[c])
						for p in ARTCD4states:
							tmpPonART[p] = 0
							PonARTData.append(tmpPonART[p])
						for q in noARTCD4states:
							tmpPnoART[q] = 0
							PnoARTData.append(tmpPnoART[q])
						out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, np.sum(popData), tmpNonAIDSdeaths, tmpTotalBirths]
						out_data.extend(popData)
						csvData.append(out_data)
					for age in xrange(15, 80, 5):
						popData = []
						tmpNewHIV = 0
						tmpDeaths = 0
						tmpHIVbirths = 0
						tmpTotalBirths = 0
						if sex == 'female' and age < 50:
							tmpTotalBirths = births[age][t]['total']
						tmpNonAIDSdeaths = 0
						HivDARTData = []
						tmpHivDART = {}
						HivDnoARTData = []
						tmpHivDnoART = {}
						PonARTData = []
						tmpPonART = {}
						PnoARTData = []
						tmpPnoART = {}
						for a in ARTCD4states:
							tmpHivDART[a] = 0
							HivDARTData.append(tmpHivDART[a])
						for b in noARTCD4states:
							tmpHivDnoART[b] = 0
							HivDnoARTData.append(tmpHivDnoART[b])
						for a5 in xrange(age, age + 5):
							tmpNonAIDSdeaths += deaths[a5][t][sex]
						for c in ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']:
							tmpPop[c] = 0
							for a5 in xrange(age, age + 5):
								if c == 'neg':
									tmpPop[c] += population[a5][t][sex][c]
							popData.append(tmpPop[c])
						for p in ARTCD4states:
							tmpPonART[p] = 0
							PonARTData.append(tmpPonART[p])
						for q in noARTCD4states:
							tmpPnoART[q] = 0
							PnoARTData.append(tmpPnoART[q])
						out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, np.sum(popData), tmpNonAIDSdeaths, tmpTotalBirths]
						out_data.extend(popData)
						csvData.append(out_data)
					age = 80
					popData = []
					tmpNewHIV = 0
					tmpDeaths = 0
					tmpHIVbirths = 0
					tmpTotalBirths = 0
					tmpNonAIDSdeaths = 0
					tmpNonAIDSdeaths = deaths[age][t][sex]
					HivDARTData = []
					tmpHivDART = {}
					HivDnoARTData = []
					tmpHivDnoART = {}
					PonARTData = []
					tmpPonART = {}
					PnoARTData = []
					tmpPnoART = {}
					for a in ARTCD4states:
						tmpHivDART[a] = 0
						HivDARTData.append(tmpHivDART[a])
					for b in noARTCD4states:
						tmpHivDnoART[b] = 0
						HivDnoARTData.append(tmpHivDnoART[b])
					for p in ARTCD4states:
						tmpPonART[p] = 0
						PonARTData.append(tmpPonART[p])
					for q in noARTCD4states:
						tmpPnoART[q] = 0
						PnoARTData.append(tmpPnoART[q])	
					for c in ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']:
						tmpPop[c] = 0
						if c == 'neg':
							tmpPop[c] += population[age][t][sex][c]
						popData.append(tmpPop[c])
					out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, np.sum(popData), tmpNonAIDSdeaths, tmpTotalBirths]
					out_data.extend(popData)
					csvData.append(out_data)

			elif output_type == 'single_year':
				for sex in sexes:
					for age in xrange(0, 15):
						popData = []
						tmpNewHIV = 0
						tmpDeaths = 0
						tmpHIVbirths = 0
						tmpNonAIDSdeaths = 0
						tmpNonAIDSdeaths += deaths[age][t][sex]
						for c in ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']:
							tmpPop[c] = 0
							if c == 'neg':
								tmpPop[c] += population[age][t][sex][c]
							popData.append(tmpPop[c])
						out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, np.sum(popData)]
						csvData.append(out_data)
					for age in xrange(15, 81):
						popData = []
						tmpNewHIV = 0
						tmpDeaths = 0
						tmpHIVbirths = 0
						tmpNonAIDSdeaths = 0
						tmpNonAIDSdeaths += deaths[age][t][sex]
						for c in ['neg', 'LT200CD4', '200to350CD4', 'GT350CD4', 'ART']:
							tmpPop[c] = 0
							if c == 'neg':
								tmpPop[c] += population[age][t][sex][c]
							popData.append(tmpPop[c])
						out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, np.sum(popData)]
						csvData.append(out_data)

			perinatalTransmission = []
			tempTotalPopByAge = {}

			allInterventionCoverage = {}
			for t in xrange(minYear, maxYear + 1):
				allInterventionCoverage[t] = {}
				for a in ['adult', 'child']:
					allInterventionCoverage[t][a] = {}
					for sex in sexes:
						allInterventionCoverage[t][a][sex] = {}
						for c in allInterventions:
							allInterventionCoverage[t][a][sex][c] = {}
							for e in ['coverage', 'eligible']:
								allInterventionCoverage[t][a][sex][c][e] = 0


			t = minYear
			for a in ['adult', 'child']:
				for sex in sexes:
					for c in allInterventions:
						coverageData.append([individual_id, t, a, sex, c, allInterventionCoverage[t][a][sex][c]['coverage'], allInterventionCoverage[t][a][sex][c]['eligible']])
			found_problem = False

			#################
			## PROJECTIONS ##
			#################
			for t in xrange(minYear + 1, maxYear + 1):
				print t
				newChildHIV = {}
				for sex in sexes:
					newChildHIV[sex] = {}
					if output_type == 'five_year':
						for age in xrange(0, 15, 5):
							newChildHIV[sex][age] = 0
					elif output_type == 'single_year':
						for age in xrange(0, 15):
							newChildHIV[sex][age] = 0
				birthsToPosMothers = {}
				for sex in sexes:
					birthsToPosMothers[sex] = {}
					if output_type == 'five_year':
						for age in xrange(0, 80, 5):
							birthsToPosMothers[sex][age] = 0
						birthsToPosMothers[sex][80] = 0
					elif output_type == 'single_year':
						for age in xrange(0, 81):
							birthsToPosMothers[sex][age] = 0
				birthsToAllMothers = {}
				for sex in sexes:
					birthsToAllMothers[sex] = {}
					if output_type == 'five_year':
						for age in xrange(0, 80, 5):
							birthsToAllMothers[sex][age] = 0
						birthsToAllMothers[sex][80] = 0
					elif output_type == 'single_year':
						for age in xrange(0, 81):
							birthsToAllMothers[sex][age] = 0

				tmpPop70noART = 0
				for sex in sexes:
					for age in population: 
						# Progress uninfected
						if age > 0 and age < max(population):
							## Project deaths for ages 1 through maxAge - 1
							sr = survivalRates[age][t][sex]
							mr = (migration[age-1][t][sex] + migration[age][t][sex]) / 2
							deaths[age][t][sex] = population[age-1][t-1][sex]['all'] * (1 - sr) + mr * (1 - sr) / 2
							
							## Project population for ages 1 through maxAge - 1
							if population[age-1][t-1][sex]['all'] < 1:
								mr = 0
							else:
								mr = mr / population[age-1][t-1][sex]['all']
							population[age][t][sex]['neg'] = population[age-1][t-1][sex]['neg'] * sr + population[age-1][t-1][sex]['neg'] * mr * (1 + sr)/2
							if population[age][t][sex]['neg'] < 0:
								population[age][t][sex]['neg'] = 0 

						# Progress infected by age group
						if age > 0 and age < max(population):
							mr = (migration[age-1][t][sex] + migration[age][t][sex]) / 2
							if population[age-1][t-1][sex]['all'] < 1:
								mr = 0
							else:
								mr = mr / population[age-1][t-1][sex]['all']
						# Children remaining under 15
						if age in xrange(1, 15):
							for h in childHIVstates[2:]:
								for d in xrange(minDuration+1, age + 2):
									population[age][t][sex][h][d] = population[age-1][t-1][sex][h][d-1] * sr + population[age-1][t-1][sex][h][d-1] * mr * (1 + sr)/2
									if population[age][t][sex][h][d] < 0:
										population[age][t][sex][h][d] = 0
						# Children becoming 15
						elif age == 15:
							NoARTCount = 0
							ARTCount = 0
							for h in childHIVstates[2:]:
								for d in xrange(minDuration, maxChildDuration + 1):
									if h == 'onFLART':
										ARTCount += population[age-1][t-1][sex][h][d]
									else:
										NoARTCount += population[age-1][t-1][sex][h][d]
							NoARTCount = NoARTCount * sr + NoARTCount * mr *  (1 + sr)/2
							if NoARTCount < 0:
								NoARTCount = 0
							ARTCount = ARTCount * sr + ARTCount * mr * (1 + sr)/2
							if ARTCount < 0:
								ARTCount = 0
							for c in noARTCD4states:
								population[age][t][sex][c] = NoARTCount * noART15CD4dist[c]
							for c in ARTCD4states[:-2]:
								population[age][t][sex][c]['GT12Mo'] = ARTCount * ART15CD4dist[c]
						# Infected Adults [16, 80)
						elif age in xrange(16, maxAge):
							mr = (migration[age-1][t][sex] + migration[age][t][sex]) / 2

							if population[age-1][t-1][sex]['all'] < 1:
								mr = 0
							else:
								mr = mr / population[age-1][t-1][sex]['all']
							for c in allCD4states:
								if c in noARTCD4states:
									population[age][t][sex][c] = population[age-1][t-1][sex][c] * sr + population[age-1][t-1][sex][c] * mr * (1 + sr) / 2
									if population[age][t][sex][c] < 0:
										population[age][t][sex][c] = 0
								else:
									for d in adultARTdurations:
										population[age][t][sex][c][d] = population[age-1][t-1][sex][c][d] * sr + population[age-1][t-1][sex][c][d] * mr * (1 + sr) / 2
										if population[age][t][sex][c][d] < 0:
											population[age][t][sex][c][d] = 0
					# Age group 80
					sr = survivalRates[80][t][sex]
					sr1 = survivalRates[81][t][sex]
					if population[79][t-1][sex]['all'] <= 0:
						mr = 0
					else:
						mr = migration[80][t][sex] + migration[79][t][sex]  / 2
					deaths[80][t][sex] = population[79][t-1][sex]['all'] * (1 - sr) + population[80][t-1][sex]['all'] * (1 - sr1) + mr * (1 - sr1) / 2
					
					if (population[79][t-1][sex]['all'] + population[80][t-1][sex]['all']) >= 1:
						mr = mr / (population[79][t-1][sex]['all'] + population[80][t-1][sex]['all'])
					else:
						mr = 0
					for c in allCD4statesNeg:
						if c in noARTCD4statesNeg:
							population[80][t][sex][c] = population[79][t-1][sex][c] * sr + population[79][t-1][sex][c] * mr * (1 + sr) / 2 + population[80][t-1][sex][c] * sr1 + population[80][t-1][sex][c] * mr * (1 + sr1) / 2
							if population[80][t][sex][c] < 0:
								population[80][t][sex][c] = 0
						else:
							for d in adultARTdurations:
								population[80][t][sex][c][d] = population[79][t-1][sex][c][d] * sr + population[79][t-1][sex][c][d] * mr * (1 + sr) / 2 + population[80][t-1][sex][c][d] * sr1 + population[80][t-1][sex][c][d] * mr * (1 + sr1) / 2							
								if population[80][t][sex][c] < 0:
									population[80][t][sex][c] = 0
				numFemales = {}
				for age in xrange(15, 50):
					numFemales[age] = 0
					for h in allCD4statesNeg:
						if h in noARTCD4statesNeg:
							numFemales[age] += population[age][t]['female'][h] + population[age][t-1]['female'][h]
						else:
							for d in adultARTdurations:
								numFemales[age] += population[age][t]['female'][h][d] + population[age][t-1]['female'][h][d]

				# Calculate the number of births
				allAgeBirths = {'male': 0, 'female': 0}
				for age in xrange(15, 50):
					births[age][t] = {}
					a5 = age - age % 5
					if t == 2014:
						print 'AGE %i' % a5
						print 'TFR: %d' % (TFR[t])
						print 'ASFRbyAge Length: %i' % (len(ASFRbyAge[a5]))
						print 't-minYear: %i' % (t-minYear)
						print 'ASFRbyAge: %d' % (ASFRbyAge[a5][t-minYear])
						print 'ASFRbyYear: %d' % np.sum(ASFRbyYear[t])
					births[age][t]['total'] = TFR[t] * (numFemales[age]) / 2 * (ASFRbyAge[a5][t-minYear] / np.sum(ASFRbyYear[t])) / 5
					births[age][t]['female'] = births[age][t]['total'] * SRB[t]
					births[age][t]['male'] = births[age][t]['total'] * (1 - SRB[t])
					allAgeBirths['male'] += births[age][t]['male']
					allAgeBirths['female'] += births[age][t]['female']

				for sex in sexes:
					sr = survivalRates[0][t][sex]
					if allAgeBirths[sex] >= 1:
						mr = migration[0][t][sex] / 2 / allAgeBirths[sex]
					else:
						mr = 0

					tempDeaths = allAgeBirths[sex] * (1 - sr) + allAgeBirths[sex] * mr * (2 * (1 - sr)) / 3
					deaths[0][t][sex] = tempDeaths
					population[0][t][sex]['neg'] = allAgeBirths[sex] * sr + allAgeBirths[sex] * mr * (1 + 2 * sr) / 3

				tempPop0_1 = population[0][t]['male']['neg'] + population[0][t]['female']['neg']

				# Push into "all" category
				updateAllStateTotal(t)
				newlyNeedingART = 0
				tempDeaths = 0
				for c in noARTCD4states:
					for sex in sexes:
						eligibleSpecialPops[c][sex] = 0

				# Calculate Adult ART coverage in current and previous two years
				allInterventionCoverage[t]['adult'][sex]['ART']['eligible'] = 0
				for sex in sexes:
					for age in xrange(childMaxAge + 1, maxAge + 1):
						ARTneed = 0
						for c in noARTCD4states:
							if CD4lowerLimits[c] < adultARTeligibility[t - minYear]:
								ARTneed += population[age][t][sex][c]
							else:
								for p in eligiblePops:
									if p != 'pregnant_women' and eligiblePopYears[p]-1 <= t:
										if not ((p == 'MSM' and sex == 'female') or (p == 'FSW' and sex == 'male')):
											ARTneed += population[age][t][sex][c] * eligiblePopPercents[p]
											eligibleSpecialPops[c][sex] += population[age][t][sex][c] * eligiblePopPercents[p]
						for c in ARTCD4states:
							for d in adultARTdurations:
								ARTneed += population[age][t][sex][c][d]
				
						# Get the number of eligible pregnant women (DPPROJA.PAS getEligiblePregnantWomen)
						# Get HIV+ women not on ART (PW)
						if 'pregnant_women' in eligiblePops:
							if sex == 'female' and age in xrange(15, 50) and eligiblePopYears['pregnant_women'] <= t:
								pregWomenNeed = getEligiblePregnantWomen(age, t)
								ARTneed += pregWomenNeed
						needForART[age][t][sex] = ARTneed
						need15plus[t][sex] += ARTneed

						allInterventionCoverage[t]['adult'][sex]['ART']['eligible'] += ARTneed

					# Calculate ART-eligible adults by state, time, age, and sex (DPPROJA.PAS 859)
					# Get ART-eligible adults by time and sex for t and up to t-2
					eligibleAdults[t-minYear][sex] = 0
					eligibleAdults[t-minYear-1][sex] = 0
					try:
						eligibleAdults[t-minYear-2][sex] = 0
					except:
						pass
					for age in xrange(15, maxAge+1):
						for c in noARTCD4states:
							if CD4lowerLimits[c] < adultARTeligibility[t-minYear]:
								eligibleAdults[t-minYear][sex] += population[age][t][sex][c]
								eligibleAdults[t-minYear-1][sex] += population[age][t-1][sex][c]
								try:
									eligibleAdults[t-minYear-2][sex] += population[age][t-2][sex][c]
								except:
									pass
							else:
								if sex == 'female' and age in xrange(15, 50):
									eligibleAdults[t-minYear][sex] += getEligiblePregnantWomen(age, t)
									eligibleAdults[t-minYear-1][sex] += getEligiblePregnantWomen(age, t-1)
									try:
										eligibleAdults[t-minYear-2][sex] += getEligiblePregnantWomen(age, t-2)
									except:
								 		pass
					# Use ART coverage to get total adult patients in a year
					try:
						if adultARTCoverageType[t-minYear-2] == 'percent':
							twoPrevYearsART[sex] = adultARTCoverage[sex][t-minYear-2] * need15plus[t-2][sex]
						else:	
							twoPrevYearsART[sex] = adultARTCoverage[sex][t-minYear-2]
					except:
						twoPrevYearsART[sex] = 0
					if adultARTCoverageType[t-minYear-1] == 'percent':
						prevYearART[sex] = adultARTCoverage[sex][t-minYear-1] * need15plus[t-1][sex] / 100
					else:
						prevYearART[sex] = adultARTCoverage[sex][t-minYear-1]
					if adultARTCoverageType[t-minYear] == 'percent':
						currentYearART[sex] = adultARTCoverage[sex][t-minYear] * need15plus[t][sex] / 100
					else:
						currentYearART[sex] = adultARTCoverage[sex][t-minYear]
					sumART = 0
				# Get adult ART survivors from previous year
				# Calculate the number of adults who needed ART for the two previous years


				ARTLT50entrants = {}
				ARTLT50deaths = {}
				for d in adultARTdurations:
					ARTLT50deaths[d] = 0
					ARTLT50entrants[d] = 0

				# Apply ART initiation, HIV/AIDS mortality, and CD4 category progression 10 times per year
				for t1 in xrange(1, 11):
					for sex in sexes:
						eligibleAdults[t - minYear][sex] = 0
						for age in xrange(15, 81):
								for c in noARTCD4states:
									if CD4lowerLimits[c] < adultARTeligibility[t-minYear]:
										eligibleAdults[t - minYear][sex] += population[age][t][sex][c]
									if sex =='female' and age in xrange(15, 50):
										eligibleAdults[t - minYear][sex] += getEligiblePregnantWomen(age, t)

						# Use ART survivors to get new adult ART patients
						ARTsurvivors = 0
						for age in xrange(15, maxAge + 1):
							age10 = ((age - (age - 5) % 10) - 15) / 10
							if age > 55:
								age10 = ((55 - (55 -5) % 10) - 15) / 10
							for c in ARTCD4states:
								for d in adultARTdurations:
									alpha = onARTmortality[sex][d][age10][c]
									ARTsurvivors += population[age][t][sex][c][d] * (1 - alpha / timeStep)
						if adultARTCoverageType[t-minYear] == 'percent':
							neededART = ARTsurvivors + (currentYearART[sex] - ARTsurvivors) / timeStep * t1
						else:
							if t1 < math.trunc(timeStep / 2):
								neededART = (twoPrevYearsART[sex] + (prevYearART[sex] - twoPrevYearsART[sex]) / timeStep
									* (t1 + (timeStep / 2)))
							else:
								neededART = (prevYearART[sex] + (currentYearART[sex] - prevYearART[sex]) / timeStep
									* (t1 - (timeStep / 2)))

						newART = neededART - ARTsurvivors
						if newART < 0:
							newART = 0

						newART = min(newART, eligibleAdults[t-minYear][sex])
						prop1 = {}
						prop2 = {}

						for c in noARTCD4states:
							eligibleAdultsCD4[c][sex] = 0
							prop1[c] = 0
							prop2[c] = 0
							if CD4lowerLimits[c] < adultARTeligibility[t-minYear]:
								for age in xrange(15, maxAge + 1):
									eligibleAdultsCD4[c][sex] += population[age][t][sex][c]
							else:
								eligibleAdultsCD4[c][sex] += eligibleSpecialPops[c][sex]
							# IF EACH CD4 CATEGORY GETS THE SAME WEIGHT IN NEW ART:
							# Get the proportion of each category by sex beginning treatment
							for i in xrange(4):
								eligByAge[i][c][sex] = 0

							if eligibleAdults[t-minYear][sex] > 0:
									prop1[c] = newART / eligibleAdults[t-minYear][sex]
							else:
								prop1[c] = 0

							for age in xrange(15, maxAge+1):
								age10 = ((age - (age - 5) % 10) - 15) / 10
								if age > 45:
									age10 = ((45 - (45 -5) % 10) - 15) / 10
								eligByAge[age10][c][sex] += population[age][t][sex][c]
							
							# Calculate all-age noART deaths for each CD4 category
							sum1 = 0
							sum2 = 0
							for a1 in xrange(4):
								mu = noARTmortality[sex][a1][c]
								sum1 += mu * eligByAge[a1][c][sex]
								sum2 += eligByAge[a1][c][sex]

							# Calculate mortality for each CD4 category
							if sum2 > 0:
								mortRate[c] = sum1/sum2
							else:
								mortRate[c] = 0

				 		# Get eligible adults by age group, CD4, and sex
						sum3 = 0
						for i in xrange(len(noARTCD4states)):
							tempSum = 0
							for c1 in noARTCD4states[i:]:
								tempSum += eligibleAdultsCD4[c1][sex] * mortRate[c1]
							if tempSum > 0:
								newPatients[noARTCD4states[i]][sex] = newART * eligibleAdultsCD4[noARTCD4states[i]][sex] * mortRate[noARTCD4states[i]] / tempSum
							else:
								newPatients[noARTCD4states[i]][sex] = 0
							newPatients[noARTCD4states[i]][sex] = min(newPatients[noARTCD4states[i]][sex], eligibleAdultsCD4[noARTCD4states[i]][sex])
							sum3 += newPatients[noARTCD4states[i]][sex]
							newART -= newPatients[noARTCD4states[i]][sex]

						# Calculate weighted average of # eligible and mortality
						for c in noARTCD4states:
							if eligibleAdultsCD4[c][sex] > 0:
								prop2[c] = newPatients[c][sex] / eligibleAdultsCD4[c][sex]
							else:
								prop2[c] = 0

							# Average the two proportions to get the distribution of new patients
							newPatients[c][sex] = (prop1[c] + prop2[c]) / 2 * eligibleAdultsCD4[c][sex]

						for age in xrange(childMaxAge + 1, maxAge + 1):
							age5 = age - age % 5
							age5_2 = (age - 15) - (age - 15) % 10 + 15
							age10 = ((age - (age - 5) % 10) - 15) / 10
							if age > 45:
								age5_2 = 45 - 45 % 5
								age10 = ((45 - (45 - 5) % 10) - 15) / 10
							age10_2 = ((age - (age - 5) % 10) - 15) / 10
							if age > 55:
								age10_2 = ((55 - (55 - 5) % 10) - 15) / 10
							GT12MoDeaths = 0
							for c in xrange(len(noARTCD4states)):
								
								beta = 0

								if eligibleAdultsCD4[noARTCD4states[c]][sex] <= 0:
									startART = 0
								else:
									if CD4lowerLimits[noARTCD4states[c]] < adultARTeligibility[t-minYear]:
										# SPECIAL POPULATIONS
										startART = min(population[age][t][sex][noARTCD4states[c]], newPatients[noARTCD4states[c]][sex] * population[age][t][sex][noARTCD4states[c]] / eligibleAdultsCD4[noARTCD4states[c]][sex])

								sumART += startART
								# Calculate noART entrants to and exits from groups
								if noARTCD4states[c] == 'GT500CD4':
									# This will be incidence
									entrants[noARTCD4states[c]][1] = 0
								else:
									# Use lambda to calculate entrants from one noART HIV+ group to another
									entrants[noARTCD4states[c]][1] = population[age][t][sex][noARTCD4states[c+1]] * progressionParameters[age5_2][sex][noARTCD4states[c+1]]
								mu = noARTmortality[sex][age10][noARTCD4states[c]]

								# Caculate the total number of exits from a group
								exits[noARTCD4states[c]][1] = (population[age][t][sex][noARTCD4states[c]] *
									(progressionParameters[age5_2][sex][noARTCD4states[c]] + mu)) + startART

								temp = min(mu * population[age][t][sex][noARTCD4states[c]], population[age][t][sex][noARTCD4states[c]])
								AIDSdeaths[age][t][sex] += max(0, temp)
								tempDeaths += temp

								AIDSdeathsCD4[age5][t][sex][noARTCD4states[c]] += max(0, temp)

								# Calculate new need for ART
								if CD4lowerLimits[noARTCD4states[c]] == adultARTeligibility[t-minYear]:
									newlyNeedingART += population[age][t][sex][noARTCD4states[c]] * progressionParameters[age5_2][sex][noARTCD4states[c]]
								# Calculate movement in the onART categories
								for d in adultARTdurations:
									alpha = onARTmortality[sex][d][age10_2][ARTCD4states[c]]
									if d == 'LT6Mo':
										entrants[ARTCD4states[c]][d] = startART
										exits[ARTCD4states[c]][d] = population[age][t][sex][ARTCD4states[c]][d] * alpha / timeStep + population[age][t][sex][ARTCD4states[c]][d] * (12 / 6) / timeStep
									elif d == '6to12Mo':
										entrants[ARTCD4states[c]][d] = population[age][t][sex][ARTCD4states[c]]['LT6Mo'] * (12 / 6) / timeStep
										exits[ARTCD4states[c]][d] = population[age][t][sex][ARTCD4states[c]][d] * alpha / timeStep + population[age][t][sex][ARTCD4states[c]][d] * (12 / 6) / timeStep
									elif d == 'GT12Mo':
										entrants[ARTCD4states[c]][d] = population[age][t][sex][ARTCD4states[c]]['6to12Mo'] * (12 / 6) / timeStep
										exits[ARTCD4states[c]][d] = population[age][t][sex][ARTCD4states[c]][d] * alpha /timeStep
										GT12MoDeaths += alpha * population[age][t][sex][ARTCD4states[c]][d] / timeStep
									temp = min(alpha * population[age][t][sex][ARTCD4states[c]][d] / timeStep, population[age][t][sex][ARTCD4states[c]][d])
									AIDSdeaths[age][t][sex] += max(0, temp)
									AIDSdeathsCD4[age5][t][sex][ARTCD4states[c]][d] += max(0, temp)

							for c in xrange(len(noARTCD4states)):
								# Add entrants and remove exits
								population[age][t][sex][noARTCD4states[c]] = max(0, population[age][t][sex][noARTCD4states[c]] + entrants[noARTCD4states[c]][1] - exits[noARTCD4states[c]][1])
								for d in adultARTdurations:
									population[age][t][sex][ARTCD4states[c]][d] = max(0, population[age][t][sex][ARTCD4states[c]][d] + entrants[ARTCD4states[c]][d] - exits[ARTCD4states[c]][d])
				updateAllStateTotal(t)									

				lastAge = 49

				susceptiblePop = {}
				for sex in sexes:
					susceptiblePop[sex] = {}
					if output_type == 'five_year':
						for age in xrange(0, 80, 5):
							susceptiblePop[sex][age] = 0
						susceptiblePop[sex][80] = 0
					elif output_type == 'single_year':
						for age in xrange(0, 81):
							susceptiblePop[sex][age] = 0


				for sex in sexes:
					for age in xrange(0, 81):
						if output_type == 'five_year':
							susceptiblePop[sex][(age - (age % 5))] += population[age][t][sex]['neg']
						elif output_type == 'single_year':
							susceptiblePop[sex][age] += population[age][t][sex]['neg']

				adults = {}
				adultHIV = {}
				neededHIV = {}
				prevRatio = {}
				for sex in sexes:
					if t == minYear + 1:
						incidenceAdjFactor = 1
					adults[sex] = 0
					adultHIV[sex] = 0

					for age in xrange(15, lastAge + 1):
						adults[sex] += population[age][t][sex]['all']
						for c in allCD4states:
							if c in noARTCD4states:
								adultHIV[sex] += population[age][t][sex][c]
							else:
								for d in adultARTdurations:
									adultHIV[sex] += population[age][t][sex][c][d]

				adults['both'] = adults['male'] + adults['female']
				adultHIV['both'] = adultHIV['male'] + adultHIV['female']

				neededHIV['both'] = adults['both'] * EPPdata[t]['prev'] / 100 - adultHIV['both']

				if neededHIV['both'] > 0 and not (EPPdata[t]['inc'] == 0 and EPPdata[t]['prev'] > 0):
					incidenceAdjFactor = (neededHIV['both'] / (adults['both'] - adultHIV['both']) * 100) / EPPdata[t]['inc']
				elif neededHIV['both'] <= 0 or (EPPdata[t]['inc'] == 0 and EPPdata[t]['prev'] > 0):
					incidenceAdjFactor = 1

				if t == 2012:
					incidenceAdjFactor2012 = float(incidenceAdjFactor)

				if t > 2012:
					incidenceAdjFactor = incidenceAdjFactor2012

				prevYearAdults = {}
				prevYearAdultHIV = {}
				for sex in sexes:
					prevYearAdultHIV[sex] = 0
					prevYearAdults[sex] = 0
					for age in xrange(15, lastAge + 1):
						prevYearAdults[sex] += population[age][t-1][sex]['all']
				 		for c in allCD4states:
							if c in noARTCD4states:
								prevYearAdultHIV[sex] += population[age][t-1][sex][c]
							else:
								for d in adultARTdurations:
									prevYearAdultHIV[sex] += population[age][t-1][sex][c][d]
				newHIV = {}

				if (prevYearAdults['female'] - prevYearAdultHIV['female'] + prevYearAdults['male'] - prevYearAdults['female']) == 0:
					temp  = 0
				else:
					temp = EPPdata[t]['inc'] / 100
				if inc_adj_config == 0:
					incidenceAdjFactor = 1
				print 'EPPdata inc:\t%f' % (EPPdata[t]['inc'])
				print 'temp:\t%f' % (temp)
				print 'ISR: %d' % incSexRatio[t-minYear]
				print 'prev: %d' % (prevYearAdults['female'] - prevYearAdultHIV['female'] + (prevYearAdults['male'] - prevYearAdultHIV['male']))
				if ((prevYearAdults['female'] - prevYearAdultHIV['female'] + (prevYearAdults['male'] - prevYearAdultHIV['male'])) > 0):
					temp = (temp * incidenceAdjFactor *
						(prevYearAdults['female'] - prevYearAdultHIV['female'] +
							prevYearAdults['male'] - prevYearAdultHIV['male']) /
						(prevYearAdults['female'] - prevYearAdultHIV['female'] +
							(prevYearAdults['male'] - prevYearAdultHIV['male']) / incSexRatio[t - minYear]))
				else:
					temp = 0

				newHIV['female'] = max(0, temp * (prevYearAdults['female'] - prevYearAdultHIV['female']))
				print 'new hiv female:\t%f' % (newHIV['female'])
				print 'suscept pop:\t%f' % (prevYearAdults['female'] - prevYearAdultHIV['female'])

				temp = temp / incSexRatio[t-minYear]

				newHIV['male'] = max(0, temp * (prevYearAdults['male'] - prevYearAdultHIV['male']))
				
				newHIV['both'] = newHIV['female'] + newHIV['male']
				
				newHIVbyAge5 = {}
				newHIVbyAge = {}
				popBy5 = {}

				for sex in sexes:
					newHIVbyAge[sex] = {}
					newHIVbyAge5[sex] = {}
					popBy5[sex] = {}
					for age in xrange(0, 15):
						newHIVbyAge[sex][age] = 0
					tempSum = 0
					pop5 = []
					ageRange = range(15,80,5)
					ageRange.append(80)
					for a5 in xrange(15, 50, 5):
						pop5.append(0)
						for age in xrange(a5, a5 + 5):
							tempSum += population[age][t][sex]['neg'] * incAgeDist[sex][0][a5]
					for a5 in ageRange:
						pop5.append(0)
						if a5 < 80:
							for age in xrange(a5, a5 + 5):
								pop5[a5/5 - 3] += population[age][t][sex]['neg']
						else:
							pop5[a5/5 - 3] += population[a5][t][sex]['neg']
					if tempSum != 0:
						adjFactor = newHIV[sex] / tempSum
					else:
						adjFactor = 0
					hiv = []
					for age in ageRange:
						hiv.append(adjFactor * incAgeDist[sex][0][age] * pop5[age/5 - 3])

					tempInterp = beers.BeersInterpolateGroups(hiv)
					
					for age in xrange(15, maxAge + 1):
						newHIVbyAge[sex][age] = tempInterp[age-15]

						if age > 45:
							age10 = ((45 - (45 - 5) % 10) - 15) / 10
						else:
							age10 = ((age - (age - 5) % 10) - 15) / 10

						for c in noARTCD4states:
							population[age][t][sex][c] += min(population[age][t][sex]['neg'], max(0, newHIVbyAge[sex][age] * initCD4dist[age10][c][sex] / 100))

						population[age][t][sex]['neg'] -= min(population[age][t][sex]['neg'], max(0, newHIVbyAge[sex][age]))

					for age5 in xrange(15, maxAge, 5):
						newHIVbyAge5[sex][age5] = 0
						popBy5[sex][age5] = 0
						for a in xrange(age5, age5 + 5):
							newHIVbyAge5[sex][age5] += newHIVbyAge[sex][a]
							popBy5[sex][age5] += population[a][t][sex]['all']



				tempBirths = 0
				tempBirths15to24 = 0
				needPMTCT = 0

				# Calculate the nubmer of births to HIV+ women
				for age5 in xrange(15, 49, 5):
					HIVwomen = 0 
					negWomen = 0
					ARTthisYear = 0
					ARTprevYear = 0
					age5c = age5/5 - 3
					for age in xrange(age5, age5 + 5):
						negWomen += (population[age][t]['female']['neg'] + population[age][t-1]['female']['neg']) / 2
						for c in allCD4states:
							if c in noARTCD4states:
								HIVwomen += (population[age][t]['female'][c] + population[age][t-1]['female'][c]) / 2
							else:
								for d in adultARTdurations:
									HIVwomen += (population[age][t]['female'][c][d] + population[age][t-1]['female'][c][d]) / 2
									ARTthisYear += population[age][t]['female'][c][d]
									ARTprevYear += population[age][t-1]['female'][c][d]

					if HIVwomen + negWomen > 0:
						prev1 = (HIVwomen - (ARTthisYear + ARTprevYear) / 2) / (HIVwomen + negWomen)
						prev2 = (HIVwomen) / (HIVwomen + negWomen)
					else:
						prev1 = 0.0
						prev2 = 0.0
					noARTbirths = ((HIVwomen - (ARTthisYear + ARTprevYear)/2) * (TFR[t]/(prev1 + (1-prev1)/TFRreduction[age5c]))
							* ((ASFRbyAge[age5][t-minYear] / np.sum(ASFRbyYear[t])) / 5))
					ARTbirths = ((ARTthisYear + ARTprevYear)/2 * TFR[t]) *  (ASFRbyAge[age5][t-minYear] / np.sum(ASFRbyYear[t])) / 5
					birthsToPosMothers['female'][age5] = noARTbirths + ARTbirths
					tempBirths += (HIVwomen * TFR[t] * TFRreduction[age5c] / (TFRreduction[age5c] * prev1 + (1 - prev1))
						* (ASFRbyAge[age5][t-minYear] / np.sum(ASFRbyYear[t])) / 5)
					birthsToAllMothers['female'][age5] = ((HIVwomen+negWomen) * TFR[t]) *  (ASFRbyAge[age5][t-minYear] / np.sum(ASFRbyYear[t])) / 5
					if age5 < 25:
						tempBirths15to24 += (HIVwomen * TFR[t] * TFRreduction[age5c] / (TFRreduction[age5c] * prev1 + (1 - prev1))
							* (ASFRbyAge[age5][t-minYear] / np.sum(ASFRbyYear[t])) / 5)
				abortion = 0
				tempBirths -= abortion
				if tempBirths < 0:
					tempBirths = 0
				needPMTCT = tempBirths

				tempBirths15to50 = tempBirths
				
				treatPercent = {}

				# Apply PMTCT
				percent_treatments = [p for p in prenatalProph.keys() if PMTCTtype['prenat'][p][t-minYear] == 'percent']
				num_treatments = [p for p in prenatalProph.keys() if PMTCTtype['prenat'][p][t-minYear] == 'num']

				tmp_denom = 0
				for p in percent_treatments:
					tmp_denom += prenatalProph[p][t-minYear] * needPMTCT / 100
				for p in num_treatments:
					tmp_denom += prenatalProph[p][t-minYear]

				denom = max(tmp_denom, needPMTCT)

				for p in PMTCTtreatmentOptions:
					treatPercent[p] = 0

				for p in num_treatments:
					if denom > 0:
						treatPercent[p] = prenatalProph[p][t-minYear] / denom
					else:
						treatPercent[p] = 0
				for p in percent_treatments:
					treatPercent[p] = prenatalProph[p][t-minYear] / 100

				tempSum = 0
				for p in treatPercent:
					if p != 'noProph':
						treatPercent[p] = min(1, treatPercent[p])
						tempSum += treatPercent[p]
				treatPercent['noProph'] = 1 - tempSum

				temppercent = dict(treatPercent)

				tempSum1 = 0
				tempSum2 = 0
				tempSum3 = 0
				for age in xrange(15, 50):
					for c in noARTCD4states[:3]:
						tempSum1 += population[age][t]['female'][c]
					tempSum2 += population[age][t]['female']['200to249CD4'] + population[age][t]['female']['250to349CD4']
					tempSum3 += population[age][t]['female']['350to500CD4'] + population[age][t]['female']['GT500CD4']

				if tempSum1 + tempSum2 + tempSum3 > 0:
					propLT200 = tempSum1 / (tempSum1 + tempSum2 + tempSum3)
					prop200to350 = tempSum2 / (tempSum1 + tempSum2 + tempSum3)
					propGE350 = tempSum3 / (tempSum1 + tempSum2 + tempSum3)
				else:
					propLT200 = 0
					prop200to350 = 1
					propGE350 = 0

				propLT350 = propLT200 + prop200to350

				if treatPercent['optionA'] + treatPercent['optionB'] > propGE350:
					if propGE350 <= 0:
						excessRatio = 0
					else:
						excessRatio = (treatPercent['optionA'] + treatPercent['optionB']) / propGE350 - 1
					optionATransRate = MTCtransRates['optionA']['perinatal'] * (1 + excessRatio)
					optionBTransRate = MTCtransRates['optionB']['perinatal'] * (1 + excessRatio)
				else:
					optionATransRate = MTCtransRates['optionA']['perinatal']
					optionBTransRate = MTCtransRates['optionB']['perinatal']

				PTR = 0
				percentInProgram = 0
				for p in treatPercent:
					if p not in ['optionA', 'optionB', 'noProph']:
						PTR += treatPercent[p] * MTCtransRates[p]['perinatal']
						percentInProgram += treatPercent[p]
				PTR += treatPercent['optionA'] * optionATransRate + treatPercent['optionB'] * optionBTransRate
				percentInProgram += treatPercent['optionA'] + treatPercent['optionB']

				tempSum1 = 0
				tempSum2 = 0
				for age5 in xrange(15, 49, 5):
					tempSum1 += newHIVbyAge5['female'][age5]
				for age in xrange(15, 50):
					for c in noARTCD4states:
						tempSum2 += population[age][t]['female'][c]
				if tempSum2 > 0:
					propIncidentInfections = tempSum1 / tempSum2
				else:
					propIncidentInfections = 0
				PTR += propIncidentInfections * treatPercent['noProph'] * MTCtransRates['IncidentInf']['perinatal']
				propGE350 = max(propGE350 - propIncidentInfections, 0)

				PTR += treatPercent['noProph'] * (1 - propIncidentInfections) * (propLT200 * MTCtransRates['LT200']['perinatal']
					+ prop200to350 * MTCtransRates['200to350']['perinatal'] + propGE350 * MTCtransRates['GT350']['perinatal'])

				perinatalTransmission.append(PTR)

				HIVbirths = max(0, tempBirths * PTR)

				print t
				print "HIV births:\t%s" % str(HIVbirths)

				newChildHIV['male'][0] += HIVbirths * (1 - SRB[t])
				newChildHIV['female'][0] += HIVbirths * SRB[t]

				sixWeekMTCT = PTR

				# BF Transmission
				
				percent_treatments = [p for p in prenatalProph.keys() if PMTCTtype['prenat'][p][t-minYear] == 'percent']
				num_treatments = [p for p in prenatalProph.keys() if PMTCTtype['prenat'][p][t-minYear] == 'num']
				percent_treatments_BF = [p for p in postnatalProph.keys() if PMTCTtype['postnat'][p][t-minYear] == 'percent']
				num_treatments_BF = [p for p in postnatalProph.keys() if PMTCTtype['postnat'][p][t-minYear] == 'num']
			
				tmp_denom = 0
				for p in percent_treatments:
					tmp_denom += prenatalProph[p][t-minYear] * needPMTCT / 100
				for p in num_treatments:
					tmp_denom += prenatalProph[p][t-minYear]

				denom = max(tmp_denom, needPMTCT)
				for p in percent_treatments:
					allInterventionCoverage[t]['adult']['female'][p]['coverage'] += prenatalProph[p][t-minYear] * denom / 100
				for p in num_treatments:
					allInterventionCoverage[t]['adult']['female'][p]['coverage'] += prenatalProph[p][t-minYear]

				for p in percent_treatments_BF:
					p_ext = p + '_BF'
					if p in ['optionA', 'optionB']:
						allInterventionCoverage[t]['adult']['female'][p_ext]['coverage'] += postnatalProph[p][t-minYear] * denom / 100
				for p in num_treatments_BF:
					p_ext = p + '_BF'
					if p in ['optionA', 'optionB']:
						allInterventionCoverage[t]['adult']['female'][p_ext]['coverage'] += postnatalProph[p][t-minYear]
	
				for p in allInterventionCoverage[t]['adult']['female']:
					if p not in ['ART', 'CTX']:
						allInterventionCoverage[t]['adult']['female'][p]['eligible'] = denom
				
				if PMTCTtype['prenat']['tripleARTdurPreg'][t-minYear] == 'percent':
					tripleARTdurPregNum = prenatalProph['tripleARTdurPreg'][t-minYear] * denom / 100
				else:
					tripleARTdurPregNum = prenatalProph['tripleARTdurPreg'][t-minYear]
				if PMTCTtype['prenat']['tripleARTbefPreg'][t-minYear] == 'percent':
					tripleARTbefPregNum = prenatalProph['tripleARTbefPreg'][t-minYear] * denom / 100
				else:
					tripleARTbefPregNum = prenatalProph['tripleARTbefPreg'][t-minYear]

				treatPercent['noProph'] = 1.0
				for p in PMTCTtreatmentOptions:
					treatPercent[p] = 0
				treatPercent['optionA_BF'] = 0
				treatPercent['optionB_BF'] = 0

				if denom > 0:
					if (denom - tripleARTbefPregNum - tripleARTdurPregNum) > 0:
						if 'optionA' in num_treatments_BF:
							treatPercent['optionA_BF'] = postnatalProph['optionA'][t-minYear] / (denom - tripleARTbefPregNum - tripleARTdurPregNum)
						if 'optionB' in num_treatments_BF:
							treatPercent['optionB_BF'] = postnatalProph['optionB'][t-minYear] / (denom - tripleARTbefPregNum - tripleARTdurPregNum)
					else:
						if 'optionA' in num_treatments_BF:
							treatPercent['optionA_BF'] = 0
						if 'optionB' in num_treatments_BF:
							treatPercent['optionB_BF'] = 0
					for p in num_treatments:
						treatPercent[p] = prenatalProph[p][t-minYear] / denom
				for p in percent_treatments:
					treatPercent[p] = prenatalProph[p][t-minYear] / 100
				for p in percent_treatments_BF:
					treatPercent[p] = postnatalProph[p][t-minYear] / 100

				tempSum = 0
				for p in treatPercent:
					if p != 'noProph':
						treatPercent[p] = min(1, treatPercent[p])
						tempSum += treatPercent[p]
				treatPercent['noProph'] = max(0, 1 - tempSum)

				BFTR = calcBFtransmission(1, 3, t)

				# Calculate infections by different time periods
				newInfFromBFLT6 = max(0, (tempBirths - HIVbirths) * BFTR)
				newChildHIV['male'][0] += newInfFromBFLT6 * (1 - SRB[t])
				newChildHIV['female'][0] += newInfFromBFLT6 * SRB[t]
				cumulNewInfFromBF = newInfFromBFLT6

				BFTR = calcBFtransmission(4, 6, t)
				newInfFromBF6to12 = max(0, (tempBirths - HIVbirths - newInfFromBFLT6) * BFTR)
				newChildHIV['male'][0] += newInfFromBF6to12 * (1 - SRB[t])
				newChildHIV['female'][0] += newInfFromBF6to12 * SRB[t]
				cumulNewInfFromBF += newInfFromBF6to12
				print "BF LT 12 Mo:\t%s" % str(cumulNewInfFromBF)

				if (cumulNewInfFromBF + HIVbirths) <= 0:
					propNewInfFromBF = 0
				else:
					propNewInfFromBF = cumulNewInfFromBF / (cumulNewInfFromBF + HIVbirths)

				if HIVbirths > 0:
					PTR = PTR * (1 + cumulNewInfFromBF / HIVbirths)

				AIDSbirths = {}
				AIDSbirths['both'] = HIVbirths
				AIDSbirths['female'] = AIDSbirths['both'] * SRB[t]
				AIDSbirths['male'] = AIDSbirths['both'] - AIDSbirths['female']

				for sex in sexes:
					sr = survivalRates[0][t][sex]

					population[0][t][sex]['asym'][1] = AIDSbirths[sex] * sr

				population[0][t]['female']['asymBFLT6Mo'][1] = newInfFromBFLT6 * SRB[t]
				population[0][t]['male']['asymBFLT6Mo'][1] = newInfFromBFLT6 * (1 - SRB[t])

				population[0][t]['female']['asymBF6to12Mo'][1] = newInfFromBF6to12 * SRB[t]
				population[0][t]['male']['asymBF6to12Mo'][1] = newInfFromBF6to12 * (1 - SRB[t])


				tempPop0_3 = population[0][t]['male']['all'] + population[0][t]['female']['all']
				for sex in sexes:
					population[0][t][sex]['neg'] -= population[0][t][sex]['asym'][1] + population[0][t][sex]['asymBFLT6Mo'][1] + population[0][t][sex]['asymBF6to12Mo'][1]
					if population[0][t][sex]['neg'] < 0:
						population[0][t][sex]['neg'] = 0

				tempNewChildInfections = HIVbirths + cumulNewInfFromBF

				if getBirths(t, 'total') <= 0:
					percentExposed = 0
				else:
					percentExposed = (tempBirths - HIVbirths - cumulNewInfFromBF) / getBirths(t, 'total')
				BFTR = calcBFtransmission(7, 12, t)

				a = 1
				for sex in sexes:
					newInfFromBFGT12 = max(0, population[a][t][sex]['neg'] * percentExposed * BFTR)
					firstYearNewInfFromBF = newInfFromBFGT12
					if sex == 'male':
						newChildHIV[sex][0] += newInfFromBFGT12 * (1 - SRB[t])
					else:
						newChildHIV[sex][0] += newInfFromBFGT12 * SRB[t]

					population[a][t][sex]['asymBFGT12Mo'][1] = newInfFromBFGT12
					population[a][t][sex]['neg'] -= newInfFromBFGT12
					cumulNewInfFromBF += newInfFromBFGT12
				print "BF FY:\t%s" % str(firstYearNewInfFromBF)

				percentExposed = percentExposed * (1 - BFTR)
				BFTR = calcBFtransmission(13, 18, t)
				a = 2
				for sex in sexes:
					newInfFromBFGT12 = max(0, population[a][t][sex]['neg'] * percentExposed * BFTR)
					if sex == 'male':
						newChildHIV[sex][0] += newInfFromBFGT12 * (1 - SRB[t])
					else:
						newChildHIV[sex][0] += newInfFromBFGT12 * SRB[t]
					secondYearNewInfFromBF = newInfFromBFGT12
					population[a][t][sex]['asymBFGT12Mo'][1] += newInfFromBFGT12
					population[a][t][sex]['neg'] -= newInfFromBFGT12
					cumulNewInfFromBF += newInfFromBFGT12
				print "BF SY:\t%s" % str(secondYearNewInfFromBF)
					
				if t > minYear + 1:
					for c in possibleCD4categories:
						childCD4countDist[t][0][c] = childCD4countDist[t-1][0][c]
						childCD4percentDist[t][0][c] = childCD4percentDist[t-1][0][c]
					for age in xrange(1, childMaxAge + 1):
						childCD4countDist[t][age][possibleCD4categories[-1]] = retentionRateCounts[possibleCD4categories[-1]] * childCD4countDist[t-1][age-1][possibleCD4categories[-1]]
						sumStart = childCD4countDist[t-1][age-1][possibleCD4categories[-1]]
						sumEnd = childCD4countDist[t][age][possibleCD4categories[-1]]

						for c in possibleCD4categories[:-1][::-1]:
							sumStart += childCD4countDist[t-1][age-1][c]
							childCD4countDist[t][age][c] = retentionRateCounts[c] * (sumStart - sumEnd)
							sumEnd += childCD4countDist[t][age][c]
					
						childCD4percentDist[t][age][possibleCD4categories[-1]] = retentionRatePercents[possibleCD4categories[-1]] * childCD4percentDist[t-1][age-1][possibleCD4categories[-1]]
						sumStart = childCD4percentDist[t-1][age-1][possibleCD4categories[-1]]
						sumEnd = childCD4percentDist[t][age][possibleCD4categories[-1]]

						for c in possibleCD4categories[:-1][::-1]:
							sumStart += childCD4percentDist[t-1][age-1][c]
							childCD4percentDist[t][age][c] = retentionRatePercents[c] * (sumStart - sumEnd)
							sumEnd += childCD4percentDist[t][age][c]

				for age in xrange(0, childMaxAge + 1):
					for sex in sexes:
						for c in childHIVstates[2:-1]:
							population[age][t][sex][c]['all'] = 0

							for d in xrange(1, age + 2):
								population[age][t][sex][c]['all'] += population[age][t][sex][c][d]		

							population[age][t]['both'][c]['all'] += population[age][t][sex][c]['all']

					population[age][t]['both']['needTx']['all'] = 0

					if ((age + 1) * 12) <= childEligibilityAge[t-minYear]:
						for c in childHIVstates[2:-1]:
							population[age][t]['both']['needTx']['all'] += population[age][t]['both'][c]['all']

					# If the age threshold is not a multiple of 12, calculate the proportion of chilren in each age group that are eligible
					# (This section returns 0 if the age threshold is a multiple of 12) 
					if ((age * 12) <= childEligibilityAge[t-minYear]) and ((a + 1) * 12 > childEligibilityAge[t-minYear]):
						population[age][t]['both']['needTx']['all'] += (childEligibilityAge[t-minYear] - age * 12) / 12 * (population[age][t]['both']['asym']['all']
							+ population[age][t]['both']['asymBFLT6Mo']['all'] + population[age][t]['both']['asymBF6to12Mo']['all']
							+ population[age][t]['both']['asymBFGT12Mo']['all'])

				for age in xrange(math.trunc(childEligibilityAge[t-minYear]/12.0), childMaxAge + 1):
					countEligible = 0
					percentEligible = 0
					age1 = monthConcordance(age)
					for c in possibleCD4categories:
						if possibleCD4categoryCounts[c] <= childEligibilityCount[age1][t-minYear]:
							countEligible += childCD4countDist[t][age][c]
						if possibleCD4categoryPercents[c] <= childEligibilityPercent[age1][t-minYear]:
							percentEligible += childCD4percentDist[t][age][c]
					if percentEligible < countEligible:
						for c in possibleCD4categories:
							if possibleCD4categoryCounts[c] <= childEligibilityCount[age1][t-minYear]:
								population[age][t]['both']['needTx']['all'] += (population[age][t]['both']['asym']['all'] + population[age][t]['both']['asymBFLT6Mo']['all'] + population[age][t]['both']['asymBF6to12Mo']['all'] + population[age][t]['both']['asymBFGT12Mo']['all'])*(childCD4countDist[t][age][c] / 100)
					else:
						for c in possibleCD4categories:
							if possibleCD4categoryPercents[c] <= childEligibilityPercent[age1][t-minYear]:
								population[age][t]['both']['needTx']['all'] += (population[age][t]['both']['asym']['all'] + population[age][t]['both']['asymBFLT6Mo']['all'] + population[age][t]['both']['asymBF6to12Mo']['all'] + population[age][t]['both']['asymBFGT12Mo']['all'])*(childCD4percentDist[t][age][c] / 100)

				unmetNeed = 0
				for age in xrange(0, childMaxAge + 1):
					unmetNeed += population[age][t]['both']['needTx']['all']

					if (population[age][t]['both']['asym']['all'] + population[age][t]['both']['asymBFLT6Mo']['all']
						+ population[age][t]['both']['asymBF6to12Mo']['all'] + population[age][t]['both']['asymBFGT12Mo']['all']) <= 0:
						population[age][t]['male']['needTx']['all'] = 0
						population[age][t]['female']['needTx']['all'] = 0
					else:
						population[age][t]['male']['needTx']['all'] = (population[age][t]['both']['needTx']['all']
							* (population[age][t]['male']['asym']['all'] + population[age][t]['male']['asymBFLT6Mo']['all']
								+ population[age][t]['male']['asymBF6to12Mo']['all'] + population[age][t]['male']['asymBFGT12Mo']['all'])
							/ (population[age][t]['both']['asym']['all'] + population[age][t]['both']['asymBFLT6Mo']['all']
								+ population[age][t]['both']['asymBF6to12Mo']['all'] + population[age][t]['both']['asymBFGT12Mo']['all']))

						population[age][t]['female']['needTx']['all'] = population[age][t]['both']['needTx']['all'] - population[age][t]['male']['needTx']['all']
				
				# Calculate chidl ART coverage
				onFLART = {}
				onFLART['both'] = 0
				for sex in sexes:
					onFLART[sex] = 0
					for age in xrange(0, childMaxAge + 1):
						for d in xrange(1, age + 2):
							onFLART['both'] += max(0, population[age][t][sex]['onFLART'][d])
							onFLART[sex] += max(0, population[age][t][sex]['onFLART'][d])

				needForFLART = unmetNeed + onFLART['both']
				allInterventionCoverage[t]['child']['female']['ART']['eligible'] += needForFLART
				
				if childARTcoverageType['ART'][t-1-minYear] == 'percent':
					ARTlastYear = needForFLART * childARTcoverage['ART'][t-1-minYear] / 100
				else:
					ARTlastYear = childARTcoverage['ART'][t-1-minYear]
				if childARTcoverageType['ART'][t-minYear] == 'percent':
					ARTthisYear = needForFLART * childARTcoverage['ART'][t-minYear] / 100
				else:
					ARTthisYear = childARTcoverage['ART'][t-minYear]

				newFLART = (ARTthisYear + ARTlastYear) / 2 - onFLART['both']
				if newFLART < 0:
					newFLART = 0

				newFLART = newFLART / (childPrSurvivalFY / (childPrSurvivalSY ** 0.5))
				if needForFLART < onFLART['both'] + newFLART:
					needForFLART = onFLART['both'] + newFLART

				HIVchildren = {}
				for sex in sexes:
					HIVchildren[sex] = 0

				for age in xrange(0, childMaxAge + 1):
					for d in xrange(1, age + 2):
						for sex in sexes:
							HIVchildren[sex] += population[age][t][sex]['asym'][d]

				if (HIVchildren['male'] + HIVchildren['female']) <= 0:
					needForFLARTmale = 0
				else:
					needForFLARTmale = needForFLART * HIVchildren['male'] / (HIVchildren['male'] + HIVchildren['female'])

				needForFLARTfemale = needForFLART - needForFLARTmale
				excess = 0
				if unmetNeed <= 0:
					temp = 1
				else:
					temp = newFLART / unmetNeed
					if temp > 1:
						temp = 1
						excess = newFLART - unmetNeed

				notOnTx = 0
				tempSum = 0
				for age in xrange(0, childMaxAge + 1):
					for sex in sexes:
						for d in xrange(1, age + 2):
							notOnTx += (population[age][t][sex]['asym'][d] + population[age][t][sex]['asymBFLT6Mo'][d]
								+ population[age][t][sex]['asymBF6to12Mo'][d] + population[age][t][sex]['asymBFGT12Mo'][d]
								+ population[age][t][sex]['needTx'][d])
							tempSum += (population[age][t][sex]['asym'][d] + population[age][t][sex]['asymBFLT6Mo'][d]
								+ population[age][t][sex]['asymBF6to12Mo'][d] + population[age][t][sex]['asymBFGT12Mo'][d])
				if notOnTx > 0:
					v2 = newFLART / notOnTx
				if tempSum > 0:
					excess = excess / tempSum
				else:
					excess = 0
				if excess > 1:
					excess = 1

				for age in xrange(minAge, childMaxAge):
					age1 = monthConcordance(age)
					if age != 0:
						for c in possibleCD4categories:
							if ((((age + 1) * 12) <= childEligibilityAge[t-minYear])
								or (possibleCD4categoryCounts[c] <= childEligibilityCount[age1][t-minYear])):
								childCD4countDist[t][age + 1][c] = childCD4countDist[t][age + 1][c] * (1 - temp)
							else:
								childCD4countDist[t][age + 1][c] = childCD4countDist[t][age + 1][c] * (1 - excess)
							if ((((age + 1) * 12) <= childEligibilityAge[t-minYear])
								or (possibleCD4categoryPercents[c] <= childEligibilityPercent[age1][t-minYear])):
								childCD4percentDist[t][age + 1][c] = childCD4percentDist[t][age + 1][c] * (1 - temp)
							else:
								childCD4percentDist[t][age+1][c] = childCD4percentDist[t][age+1][c] * (1 - excess)
						tempSum = 0
						for c in possibleCD4categories:
							tempSum += childCD4countDist[t][age+1][c]
						if tempSum > 0:
							for c  in possibleCD4categories[1:]:
								childCD4countDist[t][age + 1][c] = childCD4countDist[t][age+1][c] / (tempSum/100)
						tempSum = 0
						for c in possibleCD4categories:
							tempSum += childCD4percentDist[t][age + 1][c]
						if tempSum > 0:
							for c in possibleCD4categories[1:]:
								childCD4percentDist[t][age+1][c] = childCD4percentDist[t][age+1][c] / (tempSum/100)
					
					for sex in sexes:
						if needForFLART <= 0:
							population[age][t][sex]['onFLART'][1] = 0 
						else:
							if unmetNeed > 0:
								population[age][t][sex]['onFLART'][1] = min(population[age][t][sex]['needTx']['all'], newFLART * population[age][t][sex]['needTx']['all'] / unmetNeed)
							for d in xrange(1, age + 2):
								if notOnTx > 0:
									population[age][t][sex]['asym'][d] = population[age][t][sex]['asym'][d] * (1 - newFLART/notOnTx)
									if population[age][t][sex]['asym'][d] < 0:
										population[age][t][sex]['asym'][d] = 0

									population[age][t][sex]['asymBFLT6Mo'][d] = population[age][t][sex]['asymBFLT6Mo'][d] * (1 - newFLART / notOnTx)
									if population[age][t][sex]['asymBFLT6Mo'][d] < 0:
										population[age][t][sex]['asymBFLT6Mo'][d] = 0

									population[age][t][sex]['asymBF6to12Mo'][d] = population[age][t][sex]['asymBF6to12Mo'][d] * (1 - newFLART / notOnTx)
									if population[age][t][sex]['asymBF6to12Mo'][d] < 0:
										population[age][t][sex]['asymBF6to12Mo'][d] = 0
									
									population[age][t][sex]['asymBFGT12Mo'][d] = population[age][t][sex]['asymBFGT12Mo'][d] * (1 - newFLART / notOnTx)
									if population[age][t][sex]['asymBFGT12Mo'][d] < 0:
										population[age][t][sex]['asymBFGT12Mo'][d] = 0
				# Get CTX coverage
				posU5pop = 0
				needART5to15pop = 0
				for sex in sexes:
					for age in xrange(0, 5):
						for c in childHIVstates[2:]:
							for d in population[age][t][sex][c]:
								if d != 'all':
									posU5pop += population[age][t][sex][c][d]
				for age in xrange(5, 15):
						needART5to15pop += population[age][t]['both']['needTx']['all']

				needCTX = tempBirths15to50 * 1.5 + posU5pop + needART5to15pop
				allInterventionCoverage[t]['child']['female']['CTX']['eligible'] = needCTX
				allInterventionCoverage[t]['child']['female']['CTX']['coverage'] = min(childARTcoverage['CTX'][t-minYear], needCTX)

				if needCTX > 0:
					CTXcoverage = min(1, childARTcoverage['CTX'][t-minYear] / needCTX)
				else:
					CTXcoverage = 0
				fractionProgressing = 0

				age0fractions = []

				# Calculate child HIV/AIDS deaths
				for sex in sexes:
					for age in xrange(0, childMaxAge + 1):
						age5 = age - age % 5
						dMax = age + 1
						if t < age + 1:
							dMax = t
						for d in xrange(1, dMax+1):
							d1 = d
							if d1 > 30:
								fractionProgressing = 0
							else:
								if age == 0:
									fractionProgressing = childHIVmortality['perinatal'][age] / 100
								else:
									fractionProgressing = (childHIVmortality['perinatal'][age] - childHIVmortality['perinatal'][age-1]) / (100 - childHIVmortality['perinatal'][age-1])
							fractionProgressing *= (1 - childCTXeffect['noART'][min(d,9)] * CTXcoverage)
							if age == 0:
								age0fractions.append(fractionProgressing)

							if fractionProgressing < 0:
								fractionProgressing = 0
							if fractionProgressing > 1:
								fractionProgressing = 1
							progressors = population[age][t][sex]['asym'][d] * fractionProgressing

							population[age][t][sex]['asym'][d] -= progressors
							if population[age][t][sex]['asym'][d] < 0:
								population[age][t][sex]['asym'][d] = 0
								progressors += population[age][t][sex]['asym'][d]
							AIDSdeaths[age][t][sex] += max(0, progressors)
							AIDSdeathsCD4[age5][t][sex]['noART'] += max(0, progressors)

							fractionProgressing = fractionProgressing / (1 - childCTXeffect['noART'][min(d,9)] * CTXcoverage)
							if age == 0:
								fractionProgressing = fractionProgressing * ((1 - (childPrSurvivalFY / (childPrSurvivalSY ** .5))) * (1 - childCTXeffect['onART'][min(d,9)] * CTXcoverage))
							else:
								if d == 1:
									fractionProgressing = fractionProgressing * ((1 - (childPrSurvivalFY / (childPrSurvivalSY ** .5))) * (1 - childCTXeffect['onART'][min(d,9)] * CTXcoverage))
								else:
									fractionProgressing = fractionProgressing * ((1 - childPrSurvivalSY) * (1 - childCTXeffect['onART'][min(d, 9)] * CTXcoverage))
							if fractionProgressing < 0:
								fractionProgressing = 0
							if fractionProgressing > 1:
								fractionProgressing = 1
							progressors = population[age][t][sex]['onFLART'][d] * fractionProgressing
							population[age][t][sex]['onFLART'][d] -= progressors
							if population[age][t][sex]['onFLART'][d] < 0:
								population[age][t][sex]['onFLART'][d] = 0
							AIDSdeaths[age][t][sex] += max(0, progressors)
							AIDSdeathsCD4[age5][t][sex]['onFLART'] += max(0, progressors)

							if d1 > 30:
								fractionProgressing = 0
							else:
								if d == 1:
									fractionProgressing = childHIVmortality['postnatal0to180'][0] / 100
								else:
									fractionProgressing = (childHIVmortality['postnatal0to180'][d] - childHIVmortality['postnatal0to180'][d-1])/(100 - childHIVmortality['postnatal0to180'][d-1])
							fractionProgressing = fractionProgressing * (1 - childCTXeffect['noART'][min(d,9)] * CTXcoverage)
							
							if fractionProgressing < 0:
								fractionProgressing = 0
							if fractionProgressing > 1:
								fractionProgressing = 1
							progressors = population[age][t][sex]['asymBFLT6Mo'][d] * fractionProgressing
							population[age][t][sex]['asymBFLT6Mo'][d] -= progressors
							if population[age][t][sex]['asymBFLT6Mo'][d] < 0:
								population[age][t][sex]['asymBFLT6Mo'][d] = 0
							AIDSdeaths[age][t][sex] += max(0, progressors)
							AIDSdeathsCD4[age5][t][sex]['noART'] += max(0, progressors)
							
							if d1 > 30:
								fractionProgressing = 0
							else:
								if d == 1:
									fractionProgressing = childHIVmortality['postnatal181to365'][0] / 100
								else:
									fractionProgressing = (childHIVmortality['postnatal181to365'][d] - childHIVmortality['postnatal181to365'][d-1])/(100 - childHIVmortality['postnatal181to365'][d-1])
							fractionProgressing = fractionProgressing * (1 - childCTXeffect['noART'][min(d,9)] * CTXcoverage)
							
							if fractionProgressing < 0:
								fractionProgressing = 0
							if fractionProgressing > 1:
								fractionProgressing = 1
							progressors = population[age][t][sex]['asymBF6to12Mo'][d] * fractionProgressing
							population[age][t][sex]['asymBF6to12Mo'][d] -= progressors
							if population[age][t][sex]['asymBF6to12Mo'][d] < 0:
								population[age][t][sex]['asymBF6to12Mo'][d] = 0
							AIDSdeaths[age][t][sex] += max(0, progressors)
							AIDSdeathsCD4[age5][t][sex]['noART'] += max(0, progressors)

							if d1 > 30:
								fractionProgressing = 0
							else:
								if d == 1:
									fractionProgressing = childHIVmortality['postnatal365+'][0] / 100
								else:
									fractionProgressing = (childHIVmortality['postnatal365+'][d] - childHIVmortality['postnatal365+'][d-1])/(100 - childHIVmortality['postnatal365+'][d-1])
							fractionProgressing = fractionProgressing * (1 - childCTXeffect['noART'][min(d,9)] * CTXcoverage)
							
							if fractionProgressing < 0:
								fractionProgressing = 0
							if fractionProgressing > 1:
								fractionProgressing = 1
							progressors = population[age][t][sex]['asymBFGT12Mo'][d] * fractionProgressing
							population[age][t][sex]['asymBFGT12Mo'][d] -= progressors
							if population[age][t][sex]['asymBFGT12Mo'][d] < 0:
								population[age][t][sex]['asymBFGT12Mo'][d] = 0
							AIDSdeaths[age][t][sex] += max(0, progressors)
							AIDSdeathsCD4[age5][t][sex]['noART'] += max(0, progressors)

				updateAllStateTotal(t)

				# Prep data for output
				test_agg = 0
				tmp_SA_arr = []
				if output_type == 'five_year':
					for sex in sexes:
						for age in xrange(0, 15, 5):
							popData = []
							tmpNewHIV = newChildHIV[sex][age]
							tmpHIVbirths = 0
							tmpTotalBirths = 0
							tmpDeaths = 0
							tmpSusceptPop = susceptiblePop[sex][age]
							tmpNonAIDSdeaths = 0
							HivDARTData = []
							tmpHivDART = {}
							HivDnoARTData = []
							tmpHivDnoART = {}
							PonARTData = []
							tmpPonART = {}
							PnoARTData = []
							tmpPnoART = {}
							for a in ARTCD4states:
								tmpHivDART[a] = 0
							for b in noARTCD4states:
								tmpHivDnoART[b] = 0
							for p in ARTCD4states:
								tmpPonART[p] = 0
							for q in noARTCD4states:
								tmpPnoART[q] = 0
							tmpHivDART['ARTLT50CD4'] += AIDSdeathsCD4[age][t][sex]['onFLART']
							tmpHivDnoART['LT50CD4'] += AIDSdeathsCD4[age][t][sex]['noART']
							for c in out_cats:
								tmpPop[c] = 0
							for a5 in xrange(age, age + 5):
								tmpPopSA = 0
								tmpDeaths += AIDSdeaths[a5][t][sex]
								tmpNonAIDSdeaths += deaths[a5][t][sex]
								tmpPop['neg'] += population[a5][t][sex]['neg']
								for c_sub in ['asym', 'asymBFLT6Mo', 'asymBF6to12Mo', 'asymBFGT12Mo']:
									for d in xrange(minDuration, a5 + 2):
										tmpPopSA += population[a5][t][sex][c_sub][d]
										if sex == 'male' and age == 0:
											test_agg += population[a5][t][sex][c_sub][d]
								tmp_SA_arr.append(tmpPopSA)
								if sex == 'male' and age == 0:
									test_agg += population[a5][t][sex]['neg']
								for d in xrange(minDuration, a5 + 2):
									if sex == 'male' and age == 0:
										test_agg += population[a5][t][sex]['onFLART'][d]
									tmpPop['ART'] += population[a5][t][sex]['onFLART'][d]
									tmpPonART['ARTLT50CD4'] += population[a5][t][sex]['onFLART'][d]
								pct_LT200 = childCD4countDist[t][a5]['LT200'] / 100
								pct_200to350 = childCD4countDist[t][a5]['200to350'] / 100
								pct_GT350 = 1 - (pct_LT200 + pct_200to350)
								tmpPop['LT200CD4'] += tmpPopSA * pct_LT200
								tmpPop['200to350CD4'] += tmpPopSA * pct_200to350
								tmpPop['GT350CD4'] += tmpPopSA * pct_GT350
								tmpPnoART['LT50CD4'] += (tmpPopSA * pct_LT200) + (tmpPopSA * pct_200to350) + (tmpPopSA * pct_GT350)
							for c in out_cats:
								popData.append(tmpPop[c])
							for a in ARTCD4states:
								HivDARTData.append(tmpHivDART[a])
							for b in noARTCD4states:
								HivDnoARTData.append(tmpHivDnoART[b])
							for p in ARTCD4states:
								PonARTData.append(tmpPonART[p])
							for q in noARTCD4states:
								PnoARTData.append(tmpPnoART[q])
							if age == 0 and sex == 'male':
								frozen_pop = np.sum(tmp_SA_arr) + tmpPop['ART'] + tmpPop['neg']
							out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, tmpSusceptPop, tmpNonAIDSdeaths, tmpTotalBirths]
							out_data.extend(popData)
							csvData.append(out_data)
						for age in xrange(15, 80, 5):
							popData = []
							tmpNewHIV = newHIVbyAge5[sex][age]
							tmpHIVbirths = birthsToPosMothers[sex][age]
							tmpTotalBirths = 0
							if sex == 'female' and age < 50:
								tmpTotalBirths = birthsToAllMothers[sex][age]
							tmpDeaths = 0
							tmpSusceptPop = susceptiblePop[sex][age]
							tmpNonAIDSdeaths = 0
							HivDARTData = []
							tmpHivDART = {}
							HivDnoARTData = []
							tmpHivDnoART = {}
							PonARTData = []
							tmpPonART = {}
							PnoARTData = []
							tmpPnoART = {}
							for a in ARTCD4states:
								tmpHivDART[a] = 0
								for d in adultARTdurations:
									tmpHivDART[a] += AIDSdeathsCD4[age][t][sex][a][d]
							for b in noARTCD4states:
								tmpHivDnoART[b] = 0
								tmpHivDnoART[b] += AIDSdeathsCD4[age][t][sex][b]
							for p in ARTCD4states:
								tmpPonART[p] = 0
							for q in noARTCD4states:
								tmpPnoART[q] = 0
							for a5 in xrange(age, age + 5):
								tmpDeaths += AIDSdeaths[a5][t][sex]
								tmpNonAIDSdeaths += deaths[a5][t][sex]
							for c in out_cats:
								tmpPop[c] = 0
							for c in noARTCD4statesNeg:
								if c != 'neg':
									lower_limit = CD4lowerLimits[c]
									if lower_limit < 200:
										out_cat = 'LT200CD4'
									elif lower_limit >= 200 and lower_limit < 350:
										out_cat = '200to350CD4'
									else:
										out_cat = 'GT350CD4'
								else:
									out_cat = 'neg'
								for a5 in xrange(age, age + 5):
									tmpPop[out_cat] += population[a5][t][sex][c]
							for c in ARTCD4states:
								for d in adultARTdurations:
									for a5 in xrange(age, age + 5):
										tmpPop['ART'] += population[a5][t][sex][c][d]
										tmpPonART[c] += population[a5][t][sex][c][d]
							for c in noARTCD4states:
								for a5 in xrange(age, age + 5):
									tmpPnoART[c] += population[a5][t][sex][c]
							for c in out_cats:
								popData.append(tmpPop[c])
							for a in ARTCD4states:
								HivDARTData.append(tmpHivDART[a])
							for b in noARTCD4states:
								HivDnoARTData.append(tmpHivDnoART[b])
							for p in ARTCD4states:
								PonARTData.append(tmpPonART[p])
							for q in noARTCD4states:
								PnoARTData.append(tmpPnoART[q])
							out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, tmpSusceptPop, tmpNonAIDSdeaths, tmpTotalBirths]
							out_data.extend(popData)
							csvData.append(out_data)
						age = 80
						popData = []
						tmpNewHIV = 0
						tmpHIVbirths = 0
						tmpTotalBirths = 0
						tmpDeaths = 0
						HivDARTData = []
						tmpHivDART = {}
						HivDnoARTData = []
						tmpHivDnoART = {}
						PonARTData = []
						tmpPonART = {}
						PnoARTData = []
						tmpPnoART = {}
						for a in ARTCD4states:
							tmpHivDART[a] = 0
						for b in noARTCD4states:
							tmpHivDnoART[b] = 0
						for p in ARTCD4states:
							tmpPonART[p] = 0
						for q in noARTCD4states:
							tmpPnoART[q] = 0
						tmpDeaths += AIDSdeaths[age][t][sex]
						tmpSusceptPop = susceptiblePop[sex][age]
						tmpNonAIDSdeaths = deaths[age][t][sex]
						for a in ARTCD4states:	
							for d in adultARTdurations:
								tmpHivDART[a] += AIDSdeathsCD4[age][t][sex][a][d]
						for b in noARTCD4states:
							tmpHivDnoART[b] += AIDSdeathsCD4[age][t][sex][b]
						for c in out_cats:
							tmpPop[c] = 0
						for c in noARTCD4statesNeg:
							if c != 'neg':
								lower_limit = CD4lowerLimits[c]
								if lower_limit < 200:
									out_cat = 'LT200CD4'
								elif lower_limit >= 200 and lower_limit < 350:
									out_cat = '200to350CD4'
								else:
									out_cat = 'GT350CD4'
							else:
								out_cat = 'neg'
							tmpPop[out_cat] += population[age][t][sex][c]
						for c in ARTCD4states:
							for d in adultARTdurations:
								tmpPop['ART'] += population[age][t][sex][c][d]
								tmpPonART[c] += population[age][t][sex][c][d]
						for c in noARTCD4states:
							tmpPnoART[c] += population[age][t][sex][c]
						for c in out_cats:
							popData.append(tmpPop[c])
						for a in ARTCD4states:
							HivDARTData.append(tmpHivDART[a])
						for b in noARTCD4states:
							HivDnoARTData.append(tmpHivDnoART[b])
						for p in ARTCD4states:
							PonARTData.append(tmpPonART[p])
						for q in noARTCD4states:
							PnoARTData.append(tmpPnoART[q])
						out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpHIVbirths, tmpSusceptPop, tmpNonAIDSdeaths, tmpTotalBirths]
						out_data.extend(popData)
						csvData.append(out_data)
						
				elif output_type == 'single_year':
					for sex in sexes:
						for age in xrange(0, 15):
							popData = []
							tmpNewHIV = newChildHIV[sex][age]
							tmpHIVbirths = 0
							tmpDeaths = 0
							tmpSusceptPop = susceptiblePop[sex][age]
							tmpNonAIDSdeaths = 0
							for c in out_cats:
								tmpPop[c] = 0
							tmpPopSA = 0
							tmpDeaths += AIDSdeaths[age][t][sex]

							tmpPop['neg'] += population[age][t][sex]['neg']
							for c_sub in ['asym', 'asymBFLT6Mo', 'asymBF6to12Mo', 'asymBFGT12Mo']:
								for d in xrange(minDuration, age + 2):
									tmpPopSA += population[age][t][sex][c_sub][d]
									if sex == 'male' and age == 0:
										test_agg += population[age][t][sex][c_sub][d]
							tmp_SA_arr.append(tmpPopSA)
							if sex == 'male' and age == 0:
								test_agg += population[age][t][sex]['neg']
							for d in xrange(minDuration, age + 2):
								if sex == 'male' and age == 0:
									test_agg += population[age][t][sex]['onFLART'][d]
								tmpPop['ART'] += population[age][t][sex]['onFLART'][d]
							pct_LT200 = childCD4countDist[t][age]['LT200'] / 100
							pct_200to350 = childCD4countDist[t][age]['200to350'] / 100
							pct_GT350 = 1 - (pct_LT200 + pct_200to350)
							tmpPop['LT200CD4'] += tmpPopSA * pct_LT200
							tmpPop['200to350CD4'] += tmpPopSA * pct_200to350
							tmpPop['GT350CD4'] += tmpPopSA * pct_GT350
							for c in out_cats:
								popData.append(tmpPop[c])
							if age == 0 and sex == 'male':
								frozen_pop = np.sum(tmp_SA_arr) + tmpPop['ART'] + tmpPop['neg']
							out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpSusceptPop]
							csvData.append(out_data)
						for age in xrange(15, 81):
							popData = []
							tmpNewHIV = newHIVbyAge[sex][age]
							tmpHIVbirths = birthsToPosMothers[sex][age]
							tmpDeaths = 0
							tmpSusceptPop = susceptiblePop[sex][age]
							tmpNonAIDSdeaths = 0
							tmpDeaths += AIDSdeaths[age][t][sex]
							tmpNonAIDSdeaths += deaths[age][t][sex]
							for c in out_cats:
								tmpPop[c] = 0
							for c in noARTCD4statesNeg:
								if c != 'neg':
									lower_limit = CD4lowerLimits[c]
									if lower_limit < 200:
										out_cat = 'LT200CD4'
									elif lower_limit >= 200 and lower_limit < 350:
										out_cat = '200to350CD4'
									else:
										out_cat = 'GT350CD4'
								else:
									out_cat = 'neg'

								tmpPop[out_cat] += population[age][t][sex][c]
							for c in ARTCD4states:
								for d in adultARTdurations:
									tmpPop['ART'] += population[age][t][sex][c][d]
							for c in out_cats:
								popData.append(tmpPop[c])
							out_data = [individual_id, t, sex, age, tmpDeaths, tmpNewHIV, tmpSusceptPop]
							csvData.append(out_data)

				tmpPop0 = 0
				sex = 'male'

				# Prep coverage data for output
				for age in xrange(0, 5):
					for c in childHIVstates[1:]:
						if c == 'neg':
							tmpPop0 += population[age][t][sex][c]
						else:
							for d in xrange(minDuration, age + 2):
								tmpPop0 += population[age][t][sex][c][d]
				for sex in sexes:
					allInterventionCoverage[t]['adult'][sex]['ART']['eligible'] = 0
				for age in xrange(0, maxAge + 1):
					for sex in sexes:
						if age < 15:
							pass
							for d in xrange(minDuration, age + 2):
								allInterventionCoverage[t]['child'][sex]['ART']['coverage'] += population[age][t][sex]['onFLART'][d]
						else:
							for c in ARTCD4states:
								for d in adultARTdurations:
									allInterventionCoverage[t]['adult'][sex]['ART']['eligible'] += population[age][t][sex][c][d]
							for c in noARTCD4states:
								allInterventionCoverage[t]['adult'][sex]['ART']['eligible'] += population[age][t][sex][c]
				for sex in sexes:
					allInterventionCoverage[t]['adult'][sex]['ART']['coverage'] = min(allInterventionCoverage[t]['adult'][sex]['ART']['eligible'], currentYearART[sex])
				for a in ['adult', 'child']:
					for sex in sexes:
						for c in allInterventions:
							coverageData.append([individual_id, t, a, sex, c, allInterventionCoverage[t][a][sex][c]['coverage'], allInterventionCoverage[t][a][sex][c]['eligible']])
			end_time = round(float(time.time() - start_time) * 100) / 100
			print "Run number", individual_id, "\t", end_time
		except:
			e = traceback.format_exc()
			error = re.sub('\n', '', e)
			try:
				log_f = open(directory + '/problem_countries.csv', 'a')
			except:
				log_f = open(directory + '/problem_countries.csv', 'w')
			log_writer = csv.writer(log_f)
			log_writer.writerow([regionCode, str(error)])
			log_f.close()
if writeFiles:
	results_dir = os.path.split(directory)[-1]
	result_path = '/strPath/' + results_dir
	if not os.path.isdir(result_path):
		try:
			os.mkdir(result_path)
		except:
			pass
	result_path = result_path + '/draws/'
	print result_path
	if not os.path.isdir(result_path):
		try:
			os.mkdir(result_path)
		except:
			pass
	stage_path = result_path + stage + '/'
	if not os.path.isdir(stage_path):
		try:
			os.mkdir(stage_path)
		except:
			pass
	writePath = stage_path + regionCode + '/'
	if not os.path.isdir(writePath):
		try:
			os.mkdir(writePath)
		except:
			pass
	if counterfactual_type == 'no_ART':
		file_name = regionCode + '_no_ART_deaths_' + str(run_num) + '.csv'
	elif counterfactual_type == 'ART':
		file_name = regionCode + '_ART_deaths_' + str(run_num) + '.csv'
	elif counterfactual_type == 'HQ':
		file_name = regionCode + '_HQ_deaths_' + str(run_num) + '.csv'
	elif counterfactual_type == 'HI':
		file_name = regionCode + '_HI_deaths_' + str(run_num) + '.csv'
	testFile = open(writePath + file_name, 'w')
	wr = csv.writer(testFile)
	for row in csvData:
		wr.writerow(row)
	testFile.close()

	cov_file_name = regionCode + '_coverage_' + str(run_num) + '.csv'
	coverageFile = open(writePath + cov_file_name, 'w')
	wr = csv.writer(coverageFile)
	for row in coverageData:
		wr.writerow(row)
	coverageFile.close()

