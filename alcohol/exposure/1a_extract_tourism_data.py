"""
Extract UNWTO Tourist estimates and use them to create adjustment factors for Alcohol LPC
"""

#%%
#1. Set up global variables and file locations

import pandas as pd
from pandas import DataFrame
import string
import numpy as np
import matplotlib.pyplot as plt 
from matplotlib.backends.backend_pdf import PdfPages
import statsmodels.api as sm
import os

#Starting datasets
raw = {}

visitors_by_residence = {}
visitors_by_nationality = {}
tourists_by_residence = {}
tourists_by_nationality = {}
filtered_by_cp = {}

proportion_datasets = [['visitors_by_nationality', visitors_by_nationality], ['visitors_by_residence', visitors_by_residence], ['tourists_by_nationality', tourists_by_nationality], ['tourists_by_residence', tourists_by_residence]]
years = list(range(1995, 2015, 1))

##File locations
incoming = r'J:/DATA/UNWTO_COMPENDIUM_TOURISM_STATISTICS/1995_2014'
outgoing = "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/inputs"

template = pd.read_csv(open(r'C:\Users\strUser\Work\Data\template.csv'))
template.rename(columns={'iso3':'ihme_loc_id'}, inplace=True)

alcohol_lpc = r'J:\WORK\05_risk\risks\drugs_alcohol\data\exp\stgpr\gpr_results_alcohol_lpc.csv'

#%%
#2. Read files from incoming folder, set name of dataframe to specific countries and store in dictionary.

for files in os.listdir(incoming):
    if files.lower().endswith('.xlsx'):
        name = files.split('UNWTO_COMPENDIUM_TOURISM_STATISTICS_1995_2014_')
        name = name[1].split('_Y2016M01D12.XLSX')
        name = name[0].replace("_", " ")
        name = name.lower()
        name = string.capwords(name)
        data = pd.read_excel(incoming + '/' + files, sheetname=None, header=3, skiprows=2, na_values= ['..', '', 0], keep_default_na = False)
        raw[name] = data

#Make function to fix UNWTO location names not conforming to GBD location names
def fix_locations(data, more=False):
    location_fix = {'Antigua And Barbuda':'Antigua and Barbuda', 'Bahamas':'The Bahamas', 'Bolivia, Plurinational State Of': 'Bolivia', 'Bosnia And Herzegovina':'Bosnia and Herzegovina', 'Brunei Darussalam':'Brunei', 'Congo, Democratic Republic Of The':'Democratic Republic of the Congo', 'Cote D Ivoire':"Cote d'Ivoire", 'Gambia':'The Gambia', 'Guinea-bissau':'Guinea-Bissau', 'Hong Kong, China':'Hong Kong Special Administrative Region of China', 'Iran, Islamic Republic Of':'Iran', 'Korea, Republic Of':'South Korea', 'Macao China':'Macao Special Administrative Region of China', 'Micronesia, Federated States Of':'Federated States of Micronesia', 'Russian Federation':'Russia', 'Saint Vincent And The Grenadines':'Saint Vincent and the Grenadines', 'Sao Tome And Principe':'Sao Tome and Principe', 'State Of Palestine':'Palestine', 'Syrian Arab Republic':'Syria', 'Tanzania, United Republic Of':'Tanzania', 'Timor Leste':'Timor-Leste', 'Trinidad And Tobago':'Trinidad and Tobago', 'United States Of America':'United States', 'United States Virgin Islands':'Virgin Islands, U.S.', 'Venezuela, Bolivarian Republic Of':'Venezuela', 'Viet Nam':'Vietnam'}    
    visitors_fix = {'Bahamas':'The Bahamas', 'Belgium / Luxembourg':'Belgium', 'Bolivia, Plurinational State of': 'Bolivia', 'Brunei Darussalam':'Brunei', 'China + Hong Kong, China':'China', 'Congo, Democratic Republic of the':'Democratic Republic of the Congo', "Côte d'Ivoire":"Code d'Ivoire", 'Czech Republic/Slovakia':'Czech Republic', 'Gambia':'The Gambia', 'Hong Kong, China':'Hong Kong Special Administrative Region of China', 'India, Pakistan':'India', 'Iran, Islamic Republic of':'Iran', 'Korea, Republic of':'South Korea', "Korea, Democratic People's Republic of":'South Korea', "Lao People's Democratic Republic":'Laos', 'Macao, China':'Macao Special Administrative Region of China', 'Micronesia, Federated States of':'Federated States of Micronesia', 'Russian Federation':'Russia', 'Spain,Portugal':'Spain', 'State of Palestine':'Palestine', 'Syrian Arab Republic':'Syria', 'United Kingdom/Ireland':'United Kingdom', 'Taiwan Province of China':'Taiwan', 'Tanzania, United Republic of':'Tanzania', 'United States of America':'United States', 'United States Virgin Islands':'Virgin Islands, U.S.', 'Venezuela, Bolivarian Republic of':'Venezuela', 'Viet Nam':'Vietnam'}
    for unwto, gbd in location_fix.items():
        data['location_name'][data['location_name'] == unwto] = gbd
    if more == True:
        for unwto, gbd in location_fix.items():
            data['visiting_country'][data['visiting_country'] == unwto] = gbd
        for unwto, gbd in visitors_fix.items():
            data['visiting_country'][data['visiting_country'] == unwto] = gbd
    return data
    
#%%
#3. Read specific sheets from raw datasets and store in filtered dictionaries

for country, dataset in raw.items():
    for sheet, data in dataset.items():
        if sheet == '121':
            proportion_datasets[0][1][country] = data
        if sheet == '122':
            proportion_datasets[1][1][country] = data
        if sheet == '111':
            proportion_datasets[2][1][country] = data
        if sheet == '112':
            proportion_datasets[3][1][country] = data
        if sheet == 'CP':
            filtered_by_cp[country] = data

#%%
#4. Append filtered dictionaries, then pivot to create individual variables. Then transform to proportions

def merge_filtered(filtered, data_name):
    '''Simple function to extract data from filtered dictionaries.
       Only keeps data on countries and relevant variables. Renames variables to 
       match template.
    '''
    copy = DataFrame()
    merger = DataFrame()
    frames = {'total':[], 'visiting':[]}    
    
    for country, host in filtered.items():   
        
        #Only keep countries not regions, as well as useful indicators
        host_clean = host[host['CODE'] < 1000]
        host_clean = host_clean.drop(['CODE', '% Change 2014-2013', 'Notes', 'NOTES'], axis=1)
        
        #Rename columns and convert to long
        host_clean = host_clean.rename(columns = {'Unnamed: 2':'visiting_country'})
        
        #Get rid of pesky marketshare category
        host_clean = host_clean.iloc[:,:-1]
        
        host_clean['location_name'] = '{}'.format(country)
        host_clean = pd.melt(host_clean, id_vars=['REGION', 'location_name', 'visiting_country'], var_name='year_id', value_name=data_name)

        #Keep total separate from visiting countries
        frames['total'].append(host_clean[host_clean['visiting_country'] == 'TOTAL'])
        frames['visiting'].append(host_clean[host_clean['visiting_country'] != 'TOTAL'])
    
    #Merge visiting countries for host, keeping total separate
    merger = pd.concat(frames['total'], ignore_index=True)
    copy = pd.concat(frames['visiting'], ignore_index=True)

    #Merge copy and merger 
    merger = merger.drop(['visiting_country', 'REGION'], axis=1)
    merger = merger.rename(columns = {data_name:'Total'})  
    copy = pd.merge(copy, merger, how='right', on=['location_name', 'year_id'], sort=False)
    
    #Make sure missing observations are coded as NaN and that only countries are kept, not NaN
    for row in copy.index:
        if type(copy.iloc[row, -1]) == str:
            copy.iloc[row, -1] = np.nan
        if type(copy.iloc[row, -2]) == str:
            copy.iloc[row, -2] = np.nan
    
    #Get rid of countries with name NaN
    copy = copy[copy['visiting_country'] == copy['visiting_country']]  
    return copy

proportion_datasets_clean=[]

#Merge each category group from data extracted
for dataset in range(len(proportion_datasets)):
    proportion_datasets_clean.append(merge_filtered(proportion_datasets[dataset][1], '{}'.format(proportion_datasets[dataset][0])))
    
    #Generate tourist proportions
    proportion_datasets_clean[dataset]['tourist_proportion'] = proportion_datasets_clean[dataset].iloc[:,-2]/proportion_datasets_clean[dataset].iloc[:,-1]
    proportion_datasets_clean[dataset] = proportion_datasets_clean[dataset][['location_name', 'visiting_country', 'year_id', 'tourist_proportion']]
    proportion_datasets_clean[dataset].sort_values(['location_name', 'visiting_country', 'year_id'], inplace=True)
    
#%%
#5. Estimate full time series for tourist_proportions using kernel regression
    
def kernel_regression(dataset):
    '''Run a kernel regression on non-nan values and report predictions. 
    Set negative or infinitely small predictions to zero.
    '''        
    #Get endogenous and exogenous variables form dataset
    x = dataset['year_id'].values
    y = dataset['tourist_proportion'].values
    
    #Fix datatype issues which cause kernel regression to break    
    x = np.array(x, dtype=np.float64)
    y = np.array(y, dtype=np.float64)
    
    #Get rid of NaN datapoints and only keep observations with values
    keep = []

    for i in range(len(y)):
        if np.isnan(y[i]) == False:
            keep.append(i)
    ykeep = y[keep]
    xkeep = x[keep]
    
    #Run kernel regression and predict estimates
    kernel = sm.nonparametric.KernelReg(ykeep, xkeep, var_type='c')
    predictor = kernel.fit(years)
    predictor = predictor[0]
    
    #Bound results. No negatives or infinities. 
    for value in range(0, len(predictor)):
        if predictor[value] < 0:
            predictor[value] = 0
        if predictor[value] == np.inf: 
            predictor[value] = 0
            
    #Add kernel predictions to dataset
    dataset['predicted_values'] = predictor
    
    return dataset
 
#%%
#Define some variables we'll need.
frames = []
check_duplicates=[]

#Loop through the 4 classifications for tourists/visitors and choose preferred classification if duplicates exist. 
#Build a list of dataframes with new column values.
for dataset in proportion_datasets_clean:
    
    #Separate datasets by host country
    grouped = dataset.groupby(['location_name', 'visiting_country'])
    for (location, visiting), data in grouped:
        
    #Check that there's atleast some data
        check = np.array(data['tourist_proportion'].values, dtype=np.float64)        
        check = np.isnan(check)
        if sum(~check) >= 2:     
            
            #Check that we don't already have better data from a preferred classification dataset to ensure one 
            #dataset per country pair.
            if (location, visiting) not in check_duplicates:
                check_duplicates.append((location, visiting))
                frame = kernel_regression(data)
                frames.append(frame)                              
    
#%%Combine all of the best datasets for each country pair. Rename and add columns to prepare for kernal regression              
combine = pd.concat(frames, ignore_index=True)

#Reorder columns and sort for readability
combine.rename(columns={'tourist_proportion':'original_values'}, inplace=True)
combine = combine[['year_id', 'location_name', 'visiting_country', 'predicted_values', 'original_values']]
combine = combine.sort_values(['location_name', 'visiting_country', 'year_id'])

#Scale predicted values to 1
total = combine.groupby(['location_name', 'year_id'], as_index=False).sum()
total = total.rename(columns = {'predicted_values':'total'})

tourist_proportions = pd.merge(combine, total, how='left', on=['location_name', 'year_id'], sort=False)
tourist_proportions['scaled_tourist_proportion'] = tourist_proportions['predicted_values']/tourist_proportions['total']
tourist_proportions = tourist_proportions[tourist_proportions['scaled_tourist_proportion']!=0]

#Format so that dataset merges correctly with later datasets
fix = fix_locations(tourist_proportions, more=True)
fix.rename(columns={'location_name':'host', 'visiting_country':'location_name'}, inplace=True)
fix = pd.merge(fix, template, how='left', on=['location_name', 'year_id'])
fix = fix[['year_id', 'host', 'location_name', 'scaled_tourist_proportion', 'location_id']]
fix.rename(columns={'host':'location_name', 'location_name':'visiting_country', 'location_id':'location_id_visitor'}, inplace=True)

tourist_proportions = fix

##%%Make graphs of kernel regression results
#
#
#grouped = tourist_proportions.groupby(['location_name', 'visiting_country'], as_index=False)
#
#with PdfPages(r'C:\Users\strUser\Desktop\kernel_regression.pdf') as pdf:
#        for (host, visitor), data in grouped:
#            data.sort(columns='year_id', inplace=True)
#            
#            plt.ioff()                
#            
#            fig = plt.figure(figsize = (4,4), tight_layout=True)
#            ax = fig.add_subplot(111)
#            ax.plot(data['year_id'], data['original_values'], 'b', label='original values')
#            ax.plot(data['year_id'], data['scaled_tourist_proportion'], 'g', label='predicted values')
#            name = str(host) + ' <-- ' + str(visitor)
#            plt.title(name)
#            plt.xlabel('year_id', fontsize=8)
#            plt.ylabel('tourist_proportion', fontsize=8)
#            
#            plt.legend(loc='best')
#                
#            pdf.savefig(fig)
#            plt.close(fig)


#%% 
#6. Split cp by filtered proportions predictions to produce full time series for tourism for all countries

games = []

def merge_cp(data, country):
    '''Returns cleaned dataset for total tourism'''
    
    #Only keep relevant variables, rename, and transform the units.
    copy = data.iloc[[4, 5, 6, 54]]
    copy = copy.drop(['Cod.', 'Notes', 'Units'], axis=1)
    copy.iloc[0,0] = 'tourist_total'
    copy.iloc[1,0] = 'overnight_visitors'
    copy.iloc[2,0] = 'same_day_visitors'
    copy.iloc[3,0] = 'length_of_stay'
    copy.iloc[:-1,1:] = copy.iloc[:-1,1:]*1000
    
    #Reshape by years, then make separate columns
    copy = pd.melt(copy, id_vars=['Basic data and indicators'], var_name='year_id', value_name='data')
    copy = copy.pivot(index='year_id', columns='Basic data and indicators', values='data')
    copy['location_name'] = country
    copy['year_id'] = copy.index
    
    #Replace almost all missing values with next best estimates
    copy = next_best(copy)
    return copy

def next_best(data):
    '''Replaces tourist total with next best estimate if tourist total is missing'''
    
    if np.isnan(data['tourist_total'].values).sum() >= 19:
        data['tourist_total'] = data['overnight_visitors']
    if np.isnan(data['tourist_total'].values).sum() >= 19:
        data['tourist_total'] = data['same_day_visitors']
    return data

for country, data in filtered_by_cp.items():
    games.append(merge_cp(data, country))

#Merge on stgpr template
tourist_total = pd.concat(games, ignore_index=True)
tourist_total = fix_locations(tourist_total)
tourist_total_gpr = pd.merge(tourist_total, template, how='right', on=['location_name', 'year_id'])
tourist_total_gpr['year_id'] = tourist_total_gpr['year_id'].astype(int)

#%%
#7. Prep tourist_total for ST-GPR

def lowess(data, fraction):
    '''Calculates lowess and returns predictions'''
    
    x = data['year_id']
    y = data['data']
    
    prediction = sm.nonparametric.lowess(y, x, frac=fraction, it=10, missing='drop', return_sorted=False)
    
    return(prediction)

#Rename columns for gpr
tourist_total_gpr.rename(columns={'tourist_total':'data'}, inplace=True)

#Generate variance and SD using difference from lowess estimates
grouped = tourist_total_gpr.groupby('ihme_loc_id')
dames = []

for country, data in grouped:
    
    #Only run lowess for models with atleast 2 data points. For those with a small amount, use all of the data.    
    check = data['data'].values    
    check = np.isnan(check)    
    
    if sum(~check) >= 7:    
        lowess_hat = lowess(data, .6)
        data['lowess_hat'] = lowess_hat
        dames.append(data)
    if sum(~check) >= 4 and sum(~check) <= 6:
        lowess_hat = lowess(data, 1)
        data['lowess_hat'] = lowess_hat
        dames.append(data)

lowess_hat = pd.concat(dames, ignore_index=True)
lowess_hat = lowess_hat[['location_name', 'year_id', 'data', 'lowess_hat']]
lowess_hat.sort_values(['location_name', 'year_id'], inplace=True)

#%%
#Vet lowess model results


#def make_pdf(pair, file_location):
#    '''Creates pdf graphs from country-data pairs'''
#    
#    with PdfPages(file_location) as pdf:
#        for country, data in pair.items():
#            
#            plt.ioff()                
#            
#            fig = plt.figure(figsize = (4,4))
#            plt.plot(data['year_id'], data['data'].astype(float),  'g', label='data')
#            plt.plot(data['year_id'], data['lowess_hat'].astype(float),  'b', label='lowess_hat')
#            plt.title(country)
#            plt.xlabel('year_id', fontsize=8)
#            plt.ylabel('total_tourists', fontsize=8)
#            
#            #Make proper amount of x-ticks
#            data.dropna(inplace=True)
#            start = min(min(data['data'].values), min(data['lowess_hat'].values))
#            end = max(max(data['data'].values), max(data['lowess_hat'].values))
#            step = ((end-start)/4)
#            steps = [start, start+step, start+step*2, start+step*3, start+step*4, end]
#            plt.yticks(steps)
#                
#            plt.legend(loc='best')
#            pdf.savefig(fig)
#            plt.close(fig)
#
##Make dictionary with each country and their lowess results and use to make pdf.       
#grouped = lowess_hat.groupby('location_name')
#plots={}
#
#for location, data in grouped:
#    plots[location] = data
#
#make_pdf(plots, r'C:\Users\strUser\Desktop\variance_from_lowess_for_total_tourists_gpr.pdf')

#%%
#Collect lowess predictions with gpr prep dataset
lowess_hat = lowess_hat[['location_name', 'year_id', 'lowess_hat']]
gpr = pd.merge(tourist_total_gpr, lowess_hat, on=['location_name', 'year_id'], how='left')

gpr['residual'] = gpr['lowess_hat'] - gpr['data']

#By country, use difference between lowess estimates and data to generate variance over a 5 year window
grouped = gpr.groupby('location_name')
frames=[]

for location, data in grouped:
    data['standard_deviation'] = pd.rolling_std(data['residual'], window=5, center=True, min_periods=1)
    frames.append(data)

gpr = pd.concat(frames, ignore_index=True)

#Only hold onto variance at points where we have data. (This happens due to the rolling window)
gpr['standard_deviation'][gpr['residual'] != gpr['residual']] = np.nan
gpr['variance'] = gpr['standard_deviation']**2

gpr['constant'] = 1

#Add missing China subnational
china = template[template['location_name']=='China']
china['ihme_loc_id'] = 'CHN_44533'
china['location_id'] = 44533
china['location_name'] = 'CHN_44533'
gpr = pd.merge(gpr, china, on=['location_id', 'year_id'], how='left')

#Add on last columns needed for gpr
gpr['nid'] = 239757
gpr['me_name'] = 'total_tourists'
gpr['sample_size'] = np.nan
gpr['sex_id'] = 3
gpr['age_group_id'] = 22
gpr['age_id'] = 22

gpr.to_csv(r'J:/WORK/05_risk/risks/drugs_alcohol/data/exp/inputs/total_tourists_pre_gpr.csv')

#%%
#8. Bring in GPR results on LPC and use this, along with transformed tourism data, to create tourism adjustments

#Read in alcohol lpc gpr results and organize columns

alc_lpc = pd.read_csv(alcohol_lpc)
alc_lpc = pd.merge(alc_lpc, template, how='left', on=['location_id', 'year_id'])
alc_lpc = alc_lpc[['location_name', 'year_id', 'gpr_mean', 'location_id', 'gpr_upper', 'gpr_lower']]
alc_lpc.rename(columns={'gpr_mean':'alcohol_lpc', 'gpr_upper':'alcohol_lpc_upper', 'gpr_lower':'alcohol_lpc_lower', 'location_name':'visiting_country'}, inplace=True)
alc_lpc.drop_duplicates(inplace=True)

#Read in total tourists gpr results and organize columns

total_tourists = pd.read_csv(r'J:\WORK\05_risk\risks\drugs_alcohol\data\exp\stgpr\total_tourists.csv')
total_tourists = pd.merge(total_tourists, template, on=['ihme_loc_id', 'location_id', 'year_id'], how='left')
total_tourists = total_tourists[['ihme_loc_id', 'location_id', 'location_name', 'year_id', 'gpr_mean', 'gpr_upper', 'gpr_lower']]
total_tourists.rename(columns={'gpr_mean':'total_tourists', 'gpr_upper':'total_tourists_upper', 'gpr_lower':'total_tourists_lower'}, inplace=True)

#Merge average length of stay with total tourists. Assume 10 days when none are given (this measurement could be improved by running GPR on it)

length = tourist_total[['length_of_stay', 'location_name', 'year_id']]
total_tourists = pd.merge(total_tourists, length, on=['location_name', 'year_id'], how='inner')
total_tourists['length_of_stay'][total_tourists['length_of_stay'] != total_tourists['length_of_stay']] = 10
total_tourists['length_of_stay'] = total_tourists['length_of_stay']/365

#Merge alcohol lpc with tourist proportions by visiting countries

tourism_statistics = pd.merge(alc_lpc, tourist_proportions, how='right', on=['visiting_country', 'year_id'])
tourism_statistics = tourism_statistics[['location_name', 'year_id', 'visiting_country', 'scaled_tourist_proportion', 'alcohol_lpc', 'alcohol_lpc_lower', 'alcohol_lpc_upper']]
tourism_statistics.sort_values(['location_name', 'year_id', 'visiting_country'], inplace=True)
tourism_statistics['year_id'] = tourism_statistics['year_id'].astype(int)

#Merge host country populations on tourism statistics

pop = template[['location_name', 'year_id', 'pop_scaled']]
tourism_statistics = pd.merge(tourism_statistics, pop, on=['location_name', 'year_id'], how='left')

#Merge total tourists with tourist proportions and alcohol consumption

alc_lpc_tourists = pd.merge(tourism_statistics, total_tourists, on=['location_name', 'year_id'], how='left', indicator=True)
alc_lpc_tourists = alc_lpc_tourists[alc_lpc_tourists['_merge'] == 'both']

#Drop a confounding observation and fill some missing observation

alc_lpc_tourists = alc_lpc_tourists[alc_lpc_tourists['location_id'] != 44533]

#Assume alc_lpc is between 4-6 when none given (could be improved by taking regional averages)

alc_lpc_tourists['alcohol_lpc'][alc_lpc_tourists['alcohol_lpc'] != alc_lpc_tourists['alcohol_lpc']] = 5
alc_lpc_tourists['alcohol_lpc_lower'][alc_lpc_tourists['alcohol_lpc_lower'] != alc_lpc_tourists['alcohol_lpc_lower']] = 4
alc_lpc_tourists['alcohol_lpc_upper'][alc_lpc_tourists['alcohol_lpc_upper'] != alc_lpc_tourists['alcohol_lpc_upper']] = 6

#Generate the final estimates for additive and subtractive total tourist consumption.

alc_lpc_tourists['tourist_consumption'] = alc_lpc_tourists['scaled_tourist_proportion']*alc_lpc_tourists['alcohol_lpc']
alc_lpc_tourists['tourist_consumption_lower'] = alc_lpc_tourists['scaled_tourist_proportion']*alc_lpc_tourists['alcohol_lpc_lower']
alc_lpc_tourists['tourist_consumption_upper'] = alc_lpc_tourists['scaled_tourist_proportion']*alc_lpc_tourists['alcohol_lpc_upper']

alc_lpc_tourists['tourist_pop'] = (alc_lpc_tourists['total_tourists']*alc_lpc_tourists['length_of_stay'])
alc_lpc_tourists['tourist_pop_lower'] = (alc_lpc_tourists['total_tourists_lower']*alc_lpc_tourists['length_of_stay'])
alc_lpc_tourists['tourist_pop_upper'] = (alc_lpc_tourists['total_tourists_upper']*alc_lpc_tourists['length_of_stay'])

#Generate subtractive tourist consumption by host country = (sum(tourist_proportion*tourist_consumption)*tourist_pop)/host_pop

grouped_x = alc_lpc_tourists[['location_name', 'year_id', 'tourist_consumption', 'tourist_consumption_lower', 'tourist_consumption_upper']].groupby(['location_name', 'year_id']).sum()
grouped_y = alc_lpc_tourists[['location_name', 'year_id', 'pop_scaled', 'tourist_pop', 'tourist_pop_lower', 'tourist_pop_upper']].set_index(['location_name', 'year_id'])
grouped_y.drop_duplicates(inplace=True)

sub = pd.merge(grouped_x, grouped_y, left_index=True, right_index=True)
sub['total_tourist_consumption'] = sub['tourist_consumption']*sub['tourist_pop']/sub['pop_scaled']
sub['total_tourist_consumption_lower'] = sub['tourist_consumption_lower']*sub['tourist_pop_lower']/sub['pop_scaled'] 
sub['total_tourist_consumption_upper'] = sub['tourist_consumption_upper']*sub['tourist_pop_upper']/sub['pop_scaled']  
sub = sub.reset_index()

#Generate additive tourist consumption by visiting country = [(pop_home+sum(tourist_pop*length_of_stay))/pop_home]*alc_lpc

#%%Backcast average estimates of last three years to the years 1970-1989 to match the covariate, along with forecasting to 2015
#(Better method would be to account for changes in host country populations in addition to using this average, 
#i.e. only divide by pop_scaled after having back and forecasted values)

backcast = template[['location_name', 'year_id']]
backcast = backcast[(backcast['year_id'] <= 1994) | (backcast['year_id'] >= 2015)]
backcast = backcast.groupby('location_name')

grouped = sub.groupby('location_name')
frames = []

for country, dataset in grouped:
    dataset = dataset.append(backcast.get_group(country))
    
    avg = dataset['total_tourist_consumption'][(dataset['year_id'] >= 1995) & (dataset['year_id'] <= 1997)].mean()
    dataset['total_tourist_consumption'][dataset['total_tourist_consumption'] != dataset['total_tourist_consumption']] = avg
    temp = dataset[dataset['year_id'] == 2014].reset_index()    
    dataset['total_tourist_consumption'][dataset['year_id'] == 2015] = temp.ix[0, 'total_tourist_consumption']
    
    avg_lower = dataset['total_tourist_consumption'][(dataset['year_id'] >= 1995) & (dataset['year_id'] <= 1997)].mean()
    dataset['total_tourist_consumption_lower'][dataset['total_tourist_consumption_lower'] != dataset['total_tourist_consumption_lower']] = avg_lower
    temp = dataset[dataset['year_id'] == 2014].reset_index()
    dataset['total_tourist_consumption_lower'][dataset['year_id'] == 2015] = temp.ix[0, 'total_tourist_consumption_lower']
    
    avg_upper = dataset['total_tourist_consumption'][(dataset['year_id'] >= 1995) & (dataset['year_id'] <= 1997)].mean()
    dataset['total_tourist_consumption_upper'][dataset['total_tourist_consumption_upper'] != dataset['total_tourist_consumption_upper']] = avg_upper
    temp = dataset[dataset['year_id'] == 2014].reset_index() 
    dataset['total_tourist_consumption_upper'][dataset['year_id'] == 2015] = temp.ix[0, 'total_tourist_consumption_upper']
    
    frames.append(dataset)

sub = pd.concat(frames)

#%%Make some graphs of tourist adjusments

#grouped = sub.groupby('location_name')
#
#with PdfPages(r'C:\Users\strUser\Desktop\tourist_consumption.pdf') as pdf:
#        for country, data in grouped:
#            data.sort(columns='year_id', inplace=True)
#            
#            plt.ioff()                
#            
#            fig = plt.figure(figsize = (4,4), tight_layout=True)
#            ax = fig.add_subplot(111)
#            ax.plot(data['year_id'], data['total_tourist_consumption'])
#            ax.plot(data['year_id'], data['total_tourist_consumption_lower'], '--')
#            ax.plot(data['year_id'], data['total_tourist_consumption_upper'], '--')
#            plt.title(country)
#            plt.xlabel('year_id', fontsize=8)
#            plt.ylabel('total_tourist_consumption', fontsize=8)
#                
#            pdf.savefig(fig)
#            plt.close(fig)

#%%
#9. Combine with alc_lpc gpr results and export

alc_lpc = pd.read_csv(alcohol_lpc)
alc_lpc = pd.merge(alc_lpc, template, on=['location_id', 'ihme_loc_id', 'year_id'], how='left')
alc_lpc = pd.merge(alc_lpc, sub, on=['location_name', 'year_id'], how='left')
alc_lpc = alc_lpc[['me_name', 'ihme_loc_id', 'nid', 'source', 'location_name', 'location_id', 'year_id', 'sex_id', 'age_group_id', 'data', 'prior', 'st', 'gpr_mean', 'gpr_lower', 'gpr_upper', 'data2013', 'gpr_mean2013', 'gpr_lower2013', 'gpr_upper2013', 'total_tourist_consumption', 'total_tourist_consumption_lower', 'total_tourist_consumption_upper']]
fill = {'total_tourist_consumption':0, 'total_tourist_consumption_lower':0, 'total_tourist_consumption_upper':0}
alc_lpc['me_name'] = 'drugs_alcohol_lpc'
alc_lpc.fillna(fill, inplace=True)

alc_lpc.rename(columns={'gpr_mean':'gpr_mean_old', 'gpr_upper':'gpr_upper_old', 'gpr_lower':'gpr_lower_old'}, inplace=True)

alc_lpc['gpr_mean'] = alc_lpc['gpr_mean_old'] - alc_lpc['total_tourist_consumption']
alc_lpc['gpr_lower'] = alc_lpc['gpr_lower_old'] - alc_lpc['total_tourist_consumption_upper']
alc_lpc['gpr_upper'] = alc_lpc['gpr_upper_old'] - alc_lpc['total_tourist_consumption_lower']

#Replace some countries with old estimates, due to tourism assumptions being violated
view = alc_lpc['location_name'][alc_lpc['gpr_mean']<=0].values
view = set(view)

for country in view:
    alc_lpc['gpr_mean'][alc_lpc['location_name'] == country] = alc_lpc['gpr_mean_old']
    alc_lpc['gpr_lower'][alc_lpc['location_name'] == country] = alc_lpc['gpr_lower_old']
    alc_lpc['gpr_upper'][alc_lpc['location_name'] == country] = alc_lpc['gpr_upper_old']
    
alc_lpc.to_csv(r'J:\WORK\05_risk\risks\drugs_alcohol\data\exp\stgpr\alc_lpc_w_tourism.csv')
