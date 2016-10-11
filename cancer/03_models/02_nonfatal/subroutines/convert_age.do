** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		Script to convert to/from yld age categories and age_group_id for epi upload/download

** *********************************************************************************************************************************************************************	

capture program drop convert_to_age_group
program define convert_to_age_group
// convert from cancer nonfatal modeling age groups to epi age_group_id 
	gen age_group_id = 2 if age == 0
	replace age_group_id = 3 if age == 0.01
	replace age_group_id = 4 if age == 0.1
	replace age_group_id = 5 if age == 1
	replace age_group_id = (age/5)+5 if inrange(age, 5, 80)
	replace age_group_id = 27 if age == 98
	replace age_group_id = 22 if age == 99
end

capture program drop convert_from_age_group
program define convert_from_age_group
// convert from epi age_group_id to cancer nonfatal modeling age groups
	gen age = 99 if age_group_id == 22
	replace age = 98 if age_group_id == 27
	replace age = (age_group_id -5)*5 if inrange(age_group_id, 5, 21)
	replace age = 0 if age_group_id == 2
	replace age = 0.01 if age_group_id == 3
	replace age = 0.1 if age_group_id == 4
	replace age = 1 if age_group_id == 5
end
