# -*- coding: utf-8 -*-
"""
Description: Compiles and formats RMSE and linear prediction means to output a file used in model selection
"""

################################################################################
## SET MI Model Number (MANUAL)
################################################################################

modnums = range(165,172)

################################################################################
## 
################################################################################
## import libraries
import pandas as pd
import time, os
import openpyxl
from openpyxl.styles import Font, Color, colors

 ## define root   
j = "/home/j"

## set input and output directories    
rmse_dir = j +"/temp/registry/cancer/03_models/01_mi_ratio/RMSE"
prediction_means_dir = j +"/temp/registry/cancer/03_models/01_mi_ratio/Prediction_Means"
lm_output_dir = "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model"
output_dir = j + "/WORK/07_registry/cancer/03_models/01_mi_ratio/03_results/06_model_selection"

## Compile RMSE means
print("compiling RMSE values...")
RMSE = pd.DataFrame()
for modnum in modnums:
  filename = rmse_dir + "/RMSE_compare_"+ str(modnum) + ".csv"
  found = True if os.path.isfile(filename) else False 
  while not found: 
     if os.path.isfile(filename): found = True
     time.sleep(60)
  temp = pd.read_csv(filename)
  RMSE = RMSE.append(temp)
  print(modnum)

RMSE_output = RMSE.sort(columns=['cause', 'sex', 'mean_out_sample_rmse', 'mean_in_sample_rmse'])
RMSE_output = RMSE_output.drop_duplicates()
RMSE_output.reset_index(inplace = True)

## Verify that data is available with outliers included
RMSE_output.loc[:, 'data_available_with_outliers'] = 0
for n in range(0,RMSE_output.shape[0]):
    c = RMSE_output.loc[n,'cause']
    m = RMSE_output.loc[n,'modnum']+8
    s = RMSE_output.loc[n,'sex']
    if os.path.isfile("{}/model_{}/{}/both/linear_model_output.RData".format(lm_output_dir, m, c)) or os.path.isfile("{}/model_{}/{}/{}/linear_model_output.RData".format(lm_output_dir, m, c,s)):
        RMSE_output.loc[n, 'data_available_with_outliers'] <- 1

# compile linear prediction means
pred_means = pd.DataFrame()
print("compiling linear predictions...")
for modnum in modnums:
    print(modnum)
    ## add data from the current model number to the full dataset
    calc_by_cause = pd.read_csv(prediction_means_dir+ "/model_"+ str(modnum) + "_linear_prediction_means_byDev_andData_status.csv")
    pred_means = pred_means.append(calc_by_cause)

pred_output = pred_means.sort(columns=['cause', 'modnum', 'mean_predicted_mi'])
pred_output = pred_output.drop_duplicates()

### save
old_output = output_dir+"/model_selection_rationale_old.xlsx"
if os.path.isfile(old_output): os.remove(old_output)
new_output = output_dir + "/model_selection_rationale.xlsx"
try:
    os.rename(new_output, old_output)
except:
    pass
RMSE_output.to_excel(output_dir + "/model_selection_rationale_RMSE.xlsx", sheet_name = "RMSE", index = False, index_label = False)
pred_output.to_excel(output_dir + "/model_selection_rationale_Predictions.xlsx", sheet_name = "Linear Predictions", index = False, index_label = False)



