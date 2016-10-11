
# july 10 2016
#sdg paper: convert anc1 and ratio to anc4

rm(list=ls())
library(data.table)
library(dplyr)

# bring in anc1 numbers as dataframe
anc1_df <- fread("/share/scratch/projects/sdg/input_data/uhc/anc/anc1_draws.csv")
# bring in anc1:4 ratio
ancratio_df <- fread("/homes/X//SDG_paper/data/anc4_draws.csv")
# left join them because the anc1 numbers already have the correct locations, but anc4 numbers have too many locs
joined_df <- left_join(anc1_df, ancratio_df, by = c("location_id", "year_id", "age_group_id", "sex_id"))

# generate anc4 draws by multiplying each anc1 draw by the respective anc4 draw 
# note: decision was made not to sort the draws because that would artificially increase uncertainty
for(n in paste0("draw_", 0:999)) {
   joined_df[[n]] <- joined_df[[paste0(n, ".x")]] * joined_df[[paste0(n, ".y")]]
}

# save only the columns we need as anc4
anc4 <- joined_df[, c("year_id", "location_id", "age_group_id", "sex_id", paste0("draw_", 0:999)), with=F]

# not using: write.csv(anc4, file="/share/scratch/projects/sdg/input_data/uhc/anc/anc4_draws.csv", row.names=F)
write.csv(anc4, file="/share/scratch/projects/sdg/input_data/uhc_expanded/anc4/anc4_draws.csv", row.names=F)
# not using: write.csv(anc4, file="/share/scratch/projects/sdg/input_data/uhc_collapsed/anc/anc4_draws.csv", row.names=F)