insheet using "COM_compli.csv", comma names clear

gen standard_error = sqrt(1/sample_size * mean * (1 - mean) + 1/(4 * sample_size^2) * invnormal(0.975)^2) 
gen lower = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (mean + 1/(2*sample_size) * invnormal(0.975)^2 - invnormal(0.975) * sqrt(1/sample_size * mean * (1 - mean) + 1/(4*sample_size^2) * invnormal(0.975)^2)) 
gen upper = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (mean + 1/(2*sample_size) * invnormal(0.975)^2 + invnormal(0.975) * sqrt(1/sample_size * mean * (1 - mean) + 1/(4*sample_size^2) * invnormal(0.975)^2)) 

order complications hhseq_id mean lower upper

outsheet using "COM_complications_prepped.csv", comma names replace
