# Purpose: Regress SDG indicators against SDI


##############################################
## Set up

# Ensure required packages are installed
if (!require(foreign)) {
  install.packages("foreign", repos='http://cran.us.r-project.org')
}
if (!require(lme4)) {
  install.packages("lme4", repos='http://cran.us.r-project.org')
}
if (!require(splines)) {
  install.packages("splines", repos='http://cran.us.r-project.org')
}
if (!require(boot)) {
  install.packages("boot", repos='http://cran.us.r-project.org')
}
if (!require(plyr)) {
  install.packages("plyr", repos='http://cran.us.r-project.org')
}
if (!require(data.table)) {
  install.packages("data.table", repos='http://cran.us.r-project.org')
}
if (!require(RMySQL)) {
  install.packages("RMySQL", repos='http://cran.us.r-project.org')
}
library(ggplot2)
##############################################

## Fetch covarates
##############################################
# Get covariate
fetch.sdi <- function(lsid,
                       yidschar,
                       most_detailed=TRUE) {  
  # Do the thing
  if (most_detailed) { md <- "(1)"
  } else if (!most_detailed) md <- "(0,1)"
  con <- dbConnect(strConnection)
  covs <- dbGetQuery(con, sprintf("
          SELECT
          m.model_id,
          m.location_id,
          lhh.ihme_loc_id,
          lhh.super_region_name,
          m.year_id,
          m.age_group_id, 
          m.sex_id, 
          c.covariate_name_short,
          m.mean_value AS predictor
          FROM 
          covariate.model m
          INNER JOIN
          covariate.model_version mv ON m.model_version_id = mv.model_version_id 
          AND mv.is_best = 1
          INNER JOIN
          covariate.data_version dv ON mv.data_version_id = dv.data_version_id 
          AND dv.status = 1
          INNER JOIN
          shared.covariate c ON dv.covariate_id = c.covariate_id 
          AND c.covariate_name_short = 'sds'
          INNER JOIN 
          shared.location_hierarchy_history lhh ON m.location_id = lhh.location_id
          AND (lhh.level = 3 OR (lhh.level = 4 AND lhh.parent_id=95))
          AND lhh.location_set_version_id IN (
          SELECT 
          max(location_set_version_id) AS active_location_set_version_id
          FROM 
          shared.location_set_version 
          WHERE 
          location_set_id = %s AND 
          start_date IS NOT NULL AND
          end_date IS NULL
          )
          WHERE
          m.year_id IN (%s)
          AND m.age_group_id = 22
          AND m.sex_id = 3
  
                                  ", lsid, yidschar))
  dbDisconnect(con)
  
  # Return data frame
  return(covs)
}



# Get covariate
fetch.hale <- function(lsid,
                      yidschar,
                      most_detailed=TRUE) {  
  # Do the thing
  if (most_detailed) { md <- "(1)"
  } else if (!most_detailed) md <- "(0,1)"
  con <- dbConnect(strConnection)
  covs <- dbGetQuery(con, sprintf("
        SELECT o.location_id, year_id, lhh.ihme_loc_id, lhh.super_region_name, val AS predictor
        FROM gbd.output_hale_single_year_v269 o
                                  INNER JOIN shared.location_hierarchy_history lhh
                                  ON o.location_id = lhh.location_id
                                  AND lhh.location_set_version_id = shared.active_location_set_version(%s, 3)
                                  AND (lhh.level = 3 OR (lhh.level = 4 AND lhh.parent_id=95))
                                  WHERE age_group_id = 28
                                  AND year_id IN (%s)
                                  AND sex_id = 3
                                  
                                  ", lsid, yidschar))
  dbDisconnect(con)
  
  # Return data frame
  return(covs)
}

## Fit model
sdg.reg <- function(signal,
                      transformation="normal",
                      knots,
                      degree,
                      fitdf,
                      span=NULL) {
  ## Fit linear model with fixed effect on SDS bin
  dof <- knots + degree
  if (transformation == "log") { 
    fitdf[[signal]][fitdf[[signal]] < 1e-9] <- 1e-9
    fitdf[[signal]] <- log(fitdf[[signal]])
  } else if (transformation == "logit") { 
    fitdf[[signal]][fitdf[[signal]] < 1e-9] <- 1e-9
    fitdf[[signal]][fitdf[[signal]] > .99999999] <- .99999999
    fitdf[[signal]] <- logit(fitdf[[signal]])
  } else if (transformation != "normal") stop("Invalid transformation of dependent variable specified")
  sdg <- lm(fitdf[[signal]] ~ bs(predictor, df = dof, degree=degree), data=fitdf)

  # use this for loess (didn't find a very good spec)
  #span <- 0.25
  #sdg <- loess(fitdf[[signal]] ~ predictor, data=fitdf, span=span, degree=1)
  #sse <- sum((sdg$residuals)^2)s
  
  # Make predictions for each year and location at each SDS benchmark value
  #  (set location fixed effects to 0, reset zero and below to1 per 100 million)
  preddf <- data.frame(bin_id = seq(1, 100), predictor = seq(0.005, 0.995, .01))
  if (hale) {
    # the bin ids are weirdly hardcoded there is definitely a better way
    preddf <- data.frame(bin_id = seq(1, 48), predictor = seq(27, 74, 1))
  }
  suppressWarnings(pred_sdg <- predict(sdg,
                                         newdata=preddf))
  preds <- cbind(preddf[, c("bin_id","predictor")], pred_sdg)
  
  ## Get knots for graphing
  sdg_knots <- attr(sdg$model$bs, "knots")
  
  ## Exponentiate or inverse logit if need be, or set floor if normal
  if (transformation == "log") {
    print("taking log")
    preds$pred_sdg <- exp(preds$pred_sdg)
  } else if (transformation == "logit") {
    print("taking logit")
    preds$pred_sdg <- inv.logit(preds$pred_sdg)
  } else if (transformation == "normal") {
    print("taking normal")
    preds$pred_sdg[preds$pred_sdg <= 0] <- 1e-9
  }
  
  ## Return data frame
  return(list(preds, sdg_knots, summary(sdg)$r.squared))

  # use this for loess (this type of code is what happens in a time crunch)
  # crunch crunch crunch
  #return(list(preds, span, sse))
}

##############################################
## Graph fit


sdg.graph <- function(obs_df, exp_df, indicator_short, fit.indicator, predknots, for_paper) {
  col_grad <- colorRampPalette(c("#9E0142", "#F46D43", "#FEE08B", "#E6F598", "#66C2A5", "#5E4FA2"), space = "rgb")
  fit.text <- paste0("R-squared=", fit.indicator)
  # print(year)

  if (hale) {
    pred_var_name <- "HALE"
  } else {
    pred_var_name <- "SDI"
  }

  spline_explanation <- ""#", \nwith spline regression of index on predictor displayed as solid black line"
  
  if (for_paper) {
    if (indicator_short == "SDG Index" & !hale) {
      title <- paste0("Figure 4a. Relationship between ", 
      "Socio-demographic index and \nthe SDG ",
      "index, 2015", spline_explanation)
    } else if (indicator_short == "MDG Index" & !hale) {
      title <- paste0("Figure 4b. Relationship between Socio-demographic ",
      "index and \nthe MDG index ",
      ", 2015", spline_explanation)
    } else if (indicator_short == "Non-MDG Index" & !hale) {
      title <- paste0("Figure 4c. Relationship between Socio-demographic index ",
      "and \nthe non-MDG index",
      ", 2015", spline_explanation)
    } else if (indicator_short == "SDG Index" & hale) {
      title <- paste0("Figure 4d. Relationship between HALE ",
      "and the \nSDG index",
      ", 2015", spline_explanation)
    }
    else {
      title <- indicator_short
    }
    obs_df <- obs_df[obs_df$year_id == 2015, ]
    exp_df$psdg <- exp_df$psdg * 100.0
    obs_df$mean_val <- obs_df$mean_val * 100.0
    #p <- ggplot(obs_df, aes(sdi, mean_val))
  } else {
    title <- paste0(indicator_short, " estimate vs. prediction by ", pred_var_name)
  }

  if (hale) {
    p <- ggplot(obs_df, aes(hale, mean_val, color=factor(super_region_name)))
    p <- p + xlab("Healthy life expectancy") + ylab(indicator_short)
    p <- p + annotate("text", x=60, y=max(obs_df$mean_val), label=fit.text)
  } else {
    p <- ggplot(obs_df, aes(sdi, mean_val, color=factor(super_region_name)))
    p <- p + xlab("Socio-demographic Index") + ylab(indicator_short)
    p <- p + annotate("text", x=.5, y=max(obs_df$mean_val), label=fit.text)
  }
  p <- p + geom_point()
  p <- p + geom_line(data=exp_df, aes(predictor, psdg), inherit.aes=F, size=1)
  
  
  p <- p + ggtitle(title)
  p <- p + theme(axis.title.x = element_text(face="bold", color="black", size=12),
            axis.title.y = element_text(face="bold", color="black", size=12),
            axis.text.x = element_text(color="black", size=10),
            axis.text.y = element_text(color="black", size=10),
            plot.title = element_text(face="bold", color = "black", size=12),
            legend.position="bottom", legend.title=element_blank(),
            legend.text = element_text(size = 6))
  p <- p + scale_colour_manual(values=col_grad(length(unique(obs_df$super_region_name))))
  p <- p + guides(colour = guide_legend(nrow = 3))
  if (!for_paper) {
    #p <- p + geom_text(data = subset(obs_df, abs(mean_val-psdg) / psdg> .20), aes(label = ihme_loc_id, vjust=-.5))
    if (!is.null(predknots)) {
      for (ii in seq(1,length(predknots))) {
        p <- p + geom_vline(xintercept=as.numeric(predknots[ii]), linetype=2, color="red")
      }
    }
  } else {
    # p <- p + ylab("Health-related SDG Index")
    if (hale) {
      p <- p + scale_y_continuous(limits=c(0,100)) + scale_x_continuous(limits=c(40,80))
    } else {
      p <- p + scale_y_continuous(limits=c(0,100)) + scale_x_continuous(limits=c(0,1))
    }
    
  }
  return(p)
}


## Define how we'll format predictions predictions
format.preds <- function(preddf, predvarname) {
  preddf <- rename(preddf,c("pred_sdg" = predvarname))
  return(as.data.frame(preddf))
}

##############################################
## Run
yids <- seq(1990, 2015,5)
lsid <- 1
knots <- 3
degree <- 1
sdg_dir <- "J:/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG"
scaled <- TRUE
hale <- FALSE
for_paper <- FALSE
sdg_vers <- 16

# read indicator descriptions
indic_table <- fread(paste0(sdg_dir, "/02_inputs/indicator_ids.csv"))

# read in the covariate df - either hale or SDI
if (!hale) {
  covdf <- fetch.sdi(lsid=lsid,
                     yidschar=paste(yids, collapse=","))
  covdf <- covdf[, c('location_id', 'ihme_loc_id', 'year_id', 'super_region_name', 'predictor')]  
} else {
  covdf <- fetch.hale(lsid=lsid,
                     yidschar=paste(yids, collapse=","))
  covdf <- covdf[, c('location_id', 'ihme_loc_id', 'year_id', 'super_region_name', 'predictor')]
}


# read the mean, upper, lower of each sdg indicator
if (scaled) {
  sdgdf <- fread(paste0(sdg_dir, "/04_outputs/indicator_values/indicators_scaled_", sdg_vers,".csv"), colClasses=c(indicator_id="character"))
} else {
  sdgdf <- fread(paste0(sdg_dir, "/04_outputs/indicator_values/indicators_unscaled_", sdg_vers,".csv"), colClasses=c(indicator_id="character"))
}

sdgdf <- subset(sdgdf, select=c("location_name","location_id", "year_id", "indicator_id", "mean_val"))

if (scaled) {
  # sdg, mdg, and non-mdg indices
  indicator_ids = c(1054, 1055, 1060)
} else {
  # store vector of all indicators
  indicator_ids = unique(indic_table[indic_table$indicator_status_id == 1]$indicator_id)
}

for (indic_id in indicator_ids) {

  # fetch metadata of the indicator_id
  indicator_description <- indic_table[indic_table$indicator_id==indic_id]$ihme_indicator_description
  indicator_scale <- indic_table[indic_table$indicator_id==indic_id]$scale
  indicator_short <- indic_table[indic_table$indicator_id==indic_id]$indicator_short
  knots <- indic_table[indic_table$indicator_id==indic_id]$knots
  porder <- indic_table[indic_table$indicator_id==indic_id]$indicator_paperorder


  # prepare pdf for output
  if (!for_paper) {
    if (hale) {
      pdf(file = paste0(sdg_dir, "/04_outputs/sdi_predictions/graphs/hale/", porder, "_", indicator_short, ".pdf"))
      table_path = paste0(sdg_dir, "/04_outputs/sdi_predictions/output/hale", indicator_short, ".csv")
    } else {
      pdf(file = paste0(sdg_dir, "/04_outputs/sdi_predictions/graphs/", porder, "_", indicator_short, ".pdf"))
      table_path = paste0(sdg_dir, "/04_outputs/sdi_predictions/output/", indicator_short, ".csv")
    }
  } else {
    stopifnot(scaled)
    if (hale) {
      pdf(file = paste0(sdg_dir, "/04_outputs/figure_4_hale_prediction_of_", indicator_short,"_",sdg_vers, ".pdf"))
      table_path = paste0(sdg_dir, "/04_outputs/sdi_predictions/output/hale", indicator_short, ".csv")
    } else {
      pdf(file = paste0(sdg_dir, "/04_outputs/figure_4_sdi_prediction_of_", indicator_short,"_",sdg_vers, ".pdf"))
      table_path = paste0(sdg_dir, "/04_outputs/sdi_predictions/output/", indicator_short, ".csv")
    }
  }

  
  df <- sdgdf[sdgdf$indicator_id==indic_id]
  
  # assemble the data for the model
  drs <- data.table(merge(df, covdf, by=c('location_id', 'year_id')))

  # add a column of bin id
  if (!hale) {
    bin_id <- as.numeric(cut(drs$predictor, seq(0, 1, .01), include.lowest=TRUE))
  } else {
    min_val <- floor(min(drs$predictor))
    max_val <- ceiling(max(drs$predictor))
    bin_id <- as.numeric(cut(drs$predictor, seq(min_val, max_val, 1), include.lowest=TRUE))
  }
  drs <- cbind(drs, bin_id)

  # Set transformation and degree for the model
  if (!scaled & !hale) {
    if (indicator_scale == "infinite") {
      transformation <- "log"
    } else {
      transformation <- "logit"
    }
  } else {
    transformation <- "normal"
  }
  degree <- 1

  # Make predictions
  preds_list <- sdg.reg(signal="mean_val",
                          transformation=transformation,
                          knots=knots,
                          degree=degree,
                          fitdf=drs,
                          span = span)
  preds <- data.frame(preds_list[1])
  hyper <- preds_list[[2]]
  fit.indicator <- round(preds_list[[3]], 2)
  preds <- format.preds(preds,"psdg")
  
  ## Write csv output
  if (hale) {
    predictor_col <- "hale"
  } else {
    predictor_col <- "sdi"
  }
  obs_df <- rename(drs, c("predictor"=predictor_col))
  exp_df <- preds[, c("bin_id", "psdg", "predictor")]
  diag_df <- merge(exp_df, obs_df, by=c("bin_id"))
  #if (!for_paper) {
  write.csv(diag_df,
              table_path,
              row.names=FALSE)    
  #}
  
  ## split the title up if it is too big
  if (nchar(indicator_description) > 60) {
    isplit <- strsplit(indicator_description, " ")[[1]]
    indicator_description <- split(isplit, ceiling(seq_along(isplit)/16))  
    indicator_description <- paste0(lapply(lapply(indicator_description, paste0, collapse=" "), paste0, "\n"), collapse="")
  } else {
    indicator_description <- paste0(indicator_description, "\n")
  }

  # Make title reflect model parameters
  title=paste0(indicator_description, length(hyper), 
               " knots, ", 
               degree, 
               " degree(s), ", 
               transformation, 
               "-transformed")
  # use this for loess
  # title=paste0(indicator_description, span, " span, ", 1, " degree(s), ", transformation, "-transformed")

  # set factors of super region for ordering
  obs_df$super_region_name <- factor(obs_df$super_region_name, levels = c(
      "High-income",
      "Central Europe, Eastern Europe, and Central Asia",
      "Sub-Saharan Africa",
      "North Africa and Middle East",
      "South Asia",
      "Southeast Asia, East Asia, and Oceania",
      "Latin America and Caribbean"))
  
  p <- sdg.graph(
    obs_df=obs_df,
    exp_df=exp_df,
    indicator_short=indicator_short,
    fit.indicator=fit.indicator,
    predknots=hyper,
    for_paper=for_paper
  )
  print(p)
  dev.off()
}

##########################################################
## Wrap up
print(paste0("[", Sys.time(), "] -- COMPLETE"))
closeAllConnections()
##########################################################

