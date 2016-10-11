 quietly do strPath/save_results.do

save_results, modelable_entity_id(2006) description("upload incidence (all DM incidence and prevalence 07/14; splits from 87414, 85163, 85162, 80233") in_dir("strPath/me_2006") metrics(5 6) mark_best(yes)
save_results, modelable_entity_id(3048) description("corrected upload 07/14; splits from 87414, 85163, 85162, 80233") in_dir("strPath/me_3048") metrics(5) mark_best(yes)
save_results, modelable_entity_id(3049) description("upload 6/22; splits from 87414, 85163, 85162, 80233") in_dir("strPath/me_3049") metrics(5) mark_best(yes)
save_results, modelable_entity_id(3050) description("upload 6/22; splits from 87414, 85163, 85162, 80233") in_dir("strPath/me_3050") metrics(5) mark_best(yes)
