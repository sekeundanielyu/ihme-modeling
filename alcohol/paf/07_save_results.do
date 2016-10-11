*Save results on database

**housekeeping
clear all
set more off

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, modelable_entity_id(8762) description(alcohol mortality/morbidity) in_dir(/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output/4/) risk_type(paf) mark_best(yes) mortality(yes) morbidity(yes)

