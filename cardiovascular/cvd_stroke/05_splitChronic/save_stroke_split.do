quietly do strPath/save_results.do

save_results, modelable_entity_id(1832) description("split of 9312 by ratio of 9310 and 9311, ischemic; best models 11Jul") in_dir("strPath/ischemic") metrics(5) mark_best(yes)
save_results, modelable_entity_id(1844) description("split of 9312 by ratio of 9310 and 9311, hemorrhagic; best models 11Jul") in_dir("strPath/cerhem") metrics(5) mark_best(yes)
