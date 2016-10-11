###########################################################
### Project: ubCov
### Purpose: Calculate in-sample and OOS cross-validation statistics
### 	-RMSE
###		-Coverage
###		-Absolute Relative Error
###		-Loss
###########################################################

###################
### Setting up ####
###################
rm(list=ls())
library(plyr)
library(foreign)
library(splines)
library(boot)
library(data.table)
library(stats)
library(lme4)

source('db_tools.r')

locs<-get_location_hierarchy(74)
locs<-locs[,.(location_id, location_name, region_name, super_region_name)]

###################################################################
# Model Toggles
####################################################################

args <- commandArgs(trailingOnly = TRUE)
me_name 	 <- args[1]
data_id 	 <- args[2]
model_id     <- args[3]

model_root 	 <- paste0("/ihme/covariates/ubcov/04_model/", me_name, "/_models/", data_id, "/", model_id)

    holdout_stats<-NULL

###################################################################
# Run loop for each of the 10 holdouts
####################################################################

    for (n in 1:10) {
        # Read in the single holdout data
        df <- fread(paste0(model_root, "/", n, "/gpr.csv"), data.table = FALSE)

        # Add the geographies by which to aggregate
        df<-merge(df, locs, by='location_id', all.x=TRUE)

        # Identify training (in-sample) and test (out-of-sample) datasets
        df$train[!is.na(df$holdout)]<-0
        df$train[!is.na(df$data)]<-1
        df$data[!is.na(df$holdout)]<-df$holdout[!is.na(df$holdout)]
        df<-df[!is.na(df$data),]

        # Calculate the data coverage index
        data_count<-group_by(df, location_id, age_group_id, sex_id)
        data_count<-summarise(data_count, count = n_distinct(year_id))
        data_count<-group_by(data_count, location_id)
        data_count<-summarise(data_count, max_coverage = max(count))

        # Bin countries by data coverage
        data_count$data_coverage[data_count$max_coverage <=4]<-"0_4"
        data_count$data_coverage[data_count$max_coverage >=5 & data_count$max_coverage<=9]<-"5_9"
        data_count$data_coverage[data_count$max_coverage >=10]<-"10+"
        data_coverage<-data_count[c('data_coverage', 'location_id')]

        # Merge data coverage bins to main dataset
        df<-merge(df, data_coverage, by="location_id", all.x=TRUE)

        # Split into test and train datasets
        train<-df[df$train==1,]
        test<-df[df$train==0,]

        # Generate the metrics of interest
        train$squared_error<-(train$gpr_mean-train$data)^2
        test$squared_error<-(test$gpr_mean-test$data)^2
        train$in_ci <- ifelse(train$data >= train$gpr_lower & train$data <= train$gpr_upper, 1, 0)
        test$in_ci <- ifelse(test$data >= test$gpr_lower & test$data <= test$gpr_upper, 1, 0)
        train$are<-(abs(train$gpr_mean - train$data))/(abs(train$data))
        test$are<-(abs(test$gpr_mean - test$data))/(abs(test$data))

        # Compute metrics of interest by level of data coverage
        var<-'data_coverage'
            aggregated_is<-aggregate(train[c('in_ci', 'squared_error', 'are')], list(var=train[[var]]), mean)
            aggregated_is$squared_error<-sqrt(aggregated_is$squared_error)
            colnames(aggregated_is)<-c(paste0(var), paste0(var, "_is_coverage"), paste0(var, "_is_rmse"), paste0(var, "_is_are"))
            aggregated_is$data_coverage_is_loss<-((.95-aggregated_is$data_coverage_is_coverage)/5) + aggregated_is$data_coverage_is_are

            aggregated_oos<-aggregate(test[c('in_ci', 'squared_error', 'are')], list(var=test[[var]]), mean)
            aggregated_oos$squared_error<-sqrt(aggregated_oos$squared_error)
            colnames(aggregated_oos)<-c(paste0(var), paste0(var, "_oos_coverage"), paste0(var, "_oos_rmse"), paste0(var, "_oos_are"))
            aggregated_oos$data_coverage_oos_loss<-((.95-aggregated_oos$data_coverage_oos_coverage)/5) + aggregated_oos$data_coverage_oos_are

            out<-merge(aggregated_is, aggregated_oos, by = paste0(var), all.x=TRUE)

        # Compute global metrics of interst (OOS)
        global_oos<-setDT(test)[, lapply(.SD, mean), .SDcols=c("in_ci", "squared_error", "are")]
        colnames(global_oos) <- c('data_coverage_oos_coverage', 'data_coverage_oos_rmse', 'data_coverage_oos_are')
        global_oos$data_coverage_oos_rmse<-sqrt(global_oos$data_coverage_oos_rmse)
        global_oos$data_coverage_oos_loss<-((.95-global_oos$data_coverage_oos_coverage)/5) + global_oos$data_coverage_oos_are
        global_oos$data_coverage<-"Global"
       
        # Compute global metrics of interst (In-Sample)
        global_is<-setDT(train)[, lapply(.SD, mean), .SDcols=c("in_ci", "squared_error", "are")]
        colnames(global_is) <- c('data_coverage_is_coverage', 'data_coverage_is_rmse', 'data_coverage_is_are')
        global_is$data_coverage_is_rmse<-sqrt(global_is$data_coverage_is_rmse)
        global_is$data_coverage_is_loss<-((.95-global_is$data_coverage_is_coverage)/5) + global_is$data_coverage_is_are
        global_is$data_coverage<-"Global"

        global<-merge(global_oos, global_is, by="data_coverage", all.x=TRUE)

        holdout_stats<-rbind(holdout_stats, out)
        holdout_stats<-rbind(holdout_stats, global)
    }

#####################################################################
### Take mean and save
#####################################################################

output <- setDT(holdout_stats)[, lapply(.SD, mean), by=.(data_coverage)]

output$data_coverage <- factor(output$data_coverage, levels = c('0_4', '5_9', '10+', 'Global'))
output<-output[order(output$data_coverage),]
names(output) <- gsub("data_coverage_", "", names(output), fixed = TRUE)

output$me_name<-me_name
output$model_id<-model_id
output$data_id<-data_id

write.csv(output, paste0(model_root, "/cv.csv"), na="", row.names=FALSE)