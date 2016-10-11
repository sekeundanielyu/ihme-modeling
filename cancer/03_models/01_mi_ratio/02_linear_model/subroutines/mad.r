################################################################################

## Description: Calculates a mad centered on the mean residual and returns an outliered dataset
################################################################################
apply_madOutliers <- function(data){
  ## calculate MAD
  data$resids = data$mi_ratio - data$preds
  data$MAD <- mad(data$resids, center = mean(data$resids, na.rm = TRUE), na.rm = TRUE)

  ## replace mad with the maximum mad for age groups with few datapoints
  data$mad_distance = abs((data$resids - mean(data$resids, na.rm = TRUE))/data$MAD)  
  
  ## mark outliers
  data$outlier[data$mad_distance > 3 & data$outlier == 0] <- 1
  
  ## output troubleshooting information
  print("MAD outliers for this input:")
  mad_pts <- length(data$ihme_loc_id[data$mad_distance > 3])
  if (length(mad_pts) == 0) {print("none")} else {print(mad_pts)}
  
  ## remove irrelevant columns
  data <- data[, !(names(data) %in% c("preds", "resids", "few_datapoints", "age_mean", "MAD", "mad_distance"))]
  return(data)
}