import subprocess
				
if __name__ == '__main__':
	birth_prev_ids = [2525, 1557, 1558, 1559, 9793]
	cfr_ids = ['cfr', 'cfr1', 'cfr2', 'cfr3', 'cfr']
	mild_prop_ids = ['long_mild', 'long_mild_ga1', 'long_mild_ga2', 'long_mild_ga3', 'long_mild']
	modsev_prop_ids = ['long_modsev', 'long_modsev_ga1', 'long_modsev_ga2', 'long_modsev_ga3', 'long_modsev']
	acauses = ['neonatal_enceph', 'neonatal_preterm', 'neonatal_preterm', 'neonatal_preterm', 'neonatal_sepsis']
	zipped = zip(birth_prev_ids, cfr_ids, mild_prop_ids, modsev_prop_ids, acauses)
	
	for birth_prev, cfr, mild_prop, modsev_prop, acause in zipped:
		submission_params = ["qsub", "-P", "proj_custom_models", "-e", "/share/temp/sgeoutput/User/errors", 
						"-o", "/share/temp/sgeoutput/User/output", "-pe", "multi_slot", "10", "-l", "mem_free=20g", "-N", 
						"%s%s" % (acause, birth_prev), "/homes/User/neo_model/enceph_preterm_sepsis/model_custom/severity/run_neonatal.sh", 
						str(birth_prev), str(cfr), str(mild_prop), str(modsev_prop), str(acause)]
		print submission_params
		subprocess.check_output(submission_params)