
## sdg 2015 paper
## Generate country plots showing the UHC indicator and its components over time

###################################################################################
###################################################################################
## Purpose: these plots will be used diagnostically, to determine whether some of the 
## components are affecting the UHC indicator more or less than they should be. Also to 
## determine what is responsible for the best and worst performers' rates of change.
## We are doing this for all countries, all years 1980-2015. 
###################################################################################
###################################################################################

rm(list=ls())

library(data.table)
library(ggplot2)
library(dplyr)
library(gridExtra)


# set the current working directory to here so we can reference easier
setwd("/share/scratch/projects/sdg/indicators/")

# get locations that we will need for plotting
location_table <- function(){
    call <- 'SELECT location_id, location_name FROM 
    shared.location_hierarchy_history
    WHERE location_set_version_id=90; # gbd reporting 2015'
    con <- dbConnect(strConnection)
    res <- dbSendQuery(con, call)
    df <- fetch(res, n=-1)
    dbDisconnect(dbListConnections(MySQL())[[1]])
    df
}

# bring in the uhc indicator variable created via geometric means
uhc_ind <- fread("uhc_ind_var_post_collab.csv")
# bring in the means of every sub-indicator that goes into the uhc indicator var
uhc_sub_ind <- fread("sub_category_uhc_ind_var_post_collab.csv")

# create the mean of the sub categories
sub_draw_cols <- names(uhc_sub_ind)[grepl("_draw",  names(uhc_sub_ind))]
sub_types <- unique(sapply(strsplit(sub_draw_cols, "_draw"), function(x) x[1]))
mean_cols <- c()

for(s in sub_types){
    st_draw_sub <- sub_draw_cols[grepl(s,  sub_draw_cols)]
    new_mean <- paste0(s, "_mean")
    mean_cols <- c(mean_cols, new_mean)
    uhc_sub_ind[[new_mean]] <- rowMeans(uhc_sub_ind[,st_draw_sub, with=F])
}

# merge the two data frames together
demo_vars <- c("location_id", "age_group_id", "year_id", "sex_id", "ihme_loc_id", "location_name")
ind_vars <- c("location_id", "age_group_id", "year_id", "sex_id")

uhc_df <- left_join(uhc_ind[,c(demo_vars, "uhc_ind_var_mean"), with=F], 
                    uhc_sub_ind[,c(ind_vars, mean_cols), with=F], 
                    by=ind_vars)

# merge with locations to get location name to make plots easier to identify
# uhc_df <- left_join(uhc_df, location_table())

# make it long instead of wide for ggplot
uhc_df_melt <- melt(uhc_df, id.vars = demo_vars, 
                    measure.vars = c("uhc_ind_var_mean", mean_cols))
uhc_df_melt <- plyr::rename(uhc_df_melt, c("variable"="Indicator"))

pdf(file=paste0("./plots/","_all_locs_expanded_labeled.pdf"))

# plot each location over time and save
for(l in sort(unique(uhc_df_melt$location_name))) {
    df_sub <- subset(uhc_df_melt, location_name == l)
    df_sub[["size"]] <- (df_sub$Indicator == "uhc_ind_var_mean") + 1
    location_name <- df_sub$location_name[1]
    piloties <-ggplot(df_sub, aes(year_id, value, group = Indicator, colour = Indicator)) +
        geom_path(alpha = 0.5, aes(size = size)) + 
        geom_text(data=subset(df_sub, year_id==2015), aes(label = Indicator), hjust = 1, vjust = 1) +
        guides(size=FALSE) +
        labs(x="year", y="", title=paste0("UHC indicators and GeoMean for: ", location_name)) +
        ylim(0,1)
    #ggsave(file=paste0("./plots/", "_test.pdf"))
    print(piloties)
}

dev.off()