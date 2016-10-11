'''
Description: Runs GPR on training data and calculates loss functions for testing data
'''

import pylab as pl
import numpy as np
import os
import sys
import math
import getpass

user = getpass.getuser()
# user = sys.argv[1]
os.chdir('strPath' % (user))
# os.chdir('C:/Users/gngu/Documents/Git/adult-mortality/45q15')
# How to get the relational filepath with paste?
# os.chdir('%s/strPath/' % ('/home/j' if os.name=='posix' else 'J:'))
import gpr; reload(gpr)


'''
Get GPR settings
'''
print(sys.argv)
rr = sys.argv[1]
cc = sys.argv[2]
ho = int(sys.argv[3])
lam = sys.argv[4]
print("lambda is "+ str(lam))
zeta = sys.argv[5]
print("zeta is "+ str(zeta))

sexes = ['male','female']

## For testing
# rr = 'Central_Sub_Saharan_Africa'
# cc = 'AFG'
# ss = 'male'
# ho = int(2)
# lam = .2
# zeta = .7

# transformation for the GPR step, choose from: ('log10','ln','logit','logit10')
transform = 'logit' 

## Set seed
np.random.RandomState(intSeed)
 

'''
Import data
'''

os.chdir('strPath')

data = pl.csv2rec('prediction_model_results_all_stages_%s_%i_%s_%s.txt' % (rr, ho, lam, zeta), missing='NA')

for ss in sexes:
	# training data
	index = (data['ihme_loc_id'] == cc) & (data['sex'] == ss) & (data['data'] == 1) & (data['include'] == 'TRUE')
	train_year = pl.array(data['year'][index])
	train_mort = pl.array(data['log_mort'][index])
	train_stderr = pl.array(data['log_stderr'][index])
	train_category = pl.array(data['category'][index])

	# testing data
	index = (data['ihme_loc_id'] == cc) & (data['sex'] == ss) & (data['data'] == 1) & (data['include'] == 'FALSE')
	test_year = pl.array(data['year'][index])
	test_mort = pl.array(data['log_mort'][index])
	test_stderr = pl.array(data['log_stderr'][index])

	# prior
	index = (data['ihme_loc_id'] == cc) & (data['sex'] == ss)
	prior_year = pl.array(data['year'][index])
	if (transform == 'log10'):
		prior_mort = pl.log(pl.array(data['pred2final'][index]))/pl.log(10) # this is to convert the prior to log base-10 space
		#print('1')
	elif (transform == 'ln'):
		prior_mort = pl.log(pl.array(data['pred2final'][index])) # this is to convert the prior to natural log space
		#print('2')
	elif (transform == 'logit'):
		prior_mort = pl.log(pl.array(data['pred2final'][index])/(1 - pl.array(data['pred2final'][index]))) # this is to convert the prior to logit space
		#print('3')
	elif (transform == 'logit10'):
		prior_mort = pl.log(pl.array(data['pred2final'][index])/(1 - pl.array(data['pred2final'][index])))/pl.log(10) # this is to convert the prior to logit space
		#print('4')

	# prediction years & mse
	predictionyears = pl.array(range(int(math.floor(data['year'].min())),int(math.floor(data['year'].max()+1)))) + 0.5
	mse = data['mse'][index][0]


	'''
	Test all parameter combinations
	'''
	#amp2x_list = [0.5,0.66,1.,1.5, 2.]
	amp2x_list = [1.,1.5,2.,2.5,3.]
	scale_list = [5.,7.5,10.,12.5,15.,17.5,20.]

	# amp2x_list = [1.,2.,3.,4.,5.]
	# scale_list = [10.,15.,20.,25.,30.]

	# amp2x_list = [0.2,0.5,1.,5.,7.5,10.]
	# scale_list = [1.,5.,10.,20.,30.]

	print(len(data))
	print(len(test_mort))
	print(len(train_mort))
	# print(len(prior_mort))
	# print(predictionyears)
	# print(mse)


	if (len(test_mort) > 0):
		all_err = [] # set up holder for holdout results 
		all_est = [] # set up holder for predictions

		for amp2x in amp2x_list: # loop through amp
			for scale in scale_list: 
				print('amp2x %f and scale %f' % (amp2x, scale))
	 
				## fit model 
				if (len(train_year) == 0): # no data model 
					[M,C] = gpr.gpmodel_all(prior_mort, prior_year, scale, mse*amp2x)
					d = gpr.gpmodel_all_pred(M, C, 100, predictionyears)
				else: # data model 
					[gpmort, allobs, allyear, allvar, bias_vr, bias_sibs] = gpr.gpmodel(prior_mort, prior_year, train_mort, train_year, train_stderr, train_category, scale, mse*amp2x, cc)
					d = gpr.gpmodel_pred(gpmort, allyear, allvar, allobs, bias_vr, bias_sibs, 500, 300, 2, predictionyears)
				log_est = gpr.results(d)
				if (transform == 'log10'):
					unlog_est = gpr.results(10**d) # log base 10 space
					#print('1')
				elif (transform == 'ln'):
					unlog_est = gpr.results(math.e**d) # natural log space
					#print('2')
				elif (transform == 'logit'):
					unlog_est = gpr.results((math.e**d)/(1+(math.e**d))) # logit space
					#print('3')
				elif (transform == 'logit10'):
					unlog_est = gpr.results((10**d)/(1+(10**d))) # logit10 space
					#print('4')
					
				## save the predictions
				for i in range(len(predictionyears)):
					all_est.append((rr, cc, ss, ho, scale, amp2x, lam, zeta, mse*amp2x, predictionyears[i], unlog_est['med'][i], unlog_est['std'][i]))
				
				## calculate error and save this too 
				for year, mort, stderr in zip(test_year, test_mort, test_stderr):
					pred_index = (predictionyears == year)
					if (transform == 'log10'):
						re = (10**mort - unlog_est['med'][pred_index])/(10**mort) # log base 10
						#print('1') 
					elif (transform == 'ln'):
						re = (math.e**mort - unlog_est['med'][pred_index])/(math.e**mort) # natural log
						#print('2')
					elif (transform == 'logit'):
						re = (((math.e**mort)/(1+(math.e**mort))) - unlog_est['med'][pred_index])/((math.e**mort)/(1+(math.e**mort))) # logit
						#print('3')
					elif (transform == 'logit10'):
						re = (((10**mort)/(1+(10**mort))) - unlog_est['med'][pred_index])/((10**mort)/(1+(10**mort))) # logit
						#print('4')
					total_var = stderr**2 + log_est['std'][pred_index]**2 # This evaluates coverage as if any part of uncertainty of data and estimates overlap
					# total_var = log_est['std'][pred_index]**2 # This calculates coverage based only on the uncertainty of the estimate
					coverage = int((log_est['med'][pred_index] - 1.96*pl.sqrt(total_var)) < mort < (log_est['med'][pred_index] + 1.96*pl.sqrt(total_var)))
					all_err.append((rr, cc, ss, ho, scale, amp2x, lam, zeta, mse*amp2x, year, mort, re, coverage))
		
		## write files 
		os.chdir('/strPath')
		all_est = pl.array(all_est, [('region_name', '|S64'), ('ihme_loc_id', '|S32'), ('sex', '|S32'), ('ho', '<f8'), 
									 ('scale', '<f8'), ('amp2x', '<f8'), ('lambda', '<f8'), ('zeta', '<f8'), ('amp2', '<f8'), ('year', '<f8'), 
									 ('mort', '<f8'), ('std', '<f8')])
		pl.rec2csv(all_est, 'gpr_%s_%s_%i_%s_%s.txt' %(cc, ss, ho, lam, zeta))
		
		os.chdir('strPath')
		all_err = pl.array(all_err, [('region_name', '|S64'), ('ihme_loc_id', '|S32'), ('sex', '|S32'), ('ho', '<f8'), 
									 ('scale', '<f8'), ('amp2x', '<f8'),  ('lambda', '<f8'), ('zeta', '<f8'),('amp2', '<f8'), ('year', '<f8'), 
									 ('mort', '<f8'), ('re', '<f8'), ('coverage', '<f8')])
		pl.rec2csv(all_err, 'loss_%s_%s_%i_%s_%s.txt' %(cc, ss, ho, lam, zeta))

