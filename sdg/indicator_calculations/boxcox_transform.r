library(geoR)
library(data.table)

scale.vector <- function(X, scale) {
  # Scale a vector using an optimized boxcox transformation
  if (unique(scale) == "infinite") {
    Y <- tryCatch({
      if (length(X[X==0]) == 0) {
        warning("No 0s to optimize lambda2, just using lambda1.")
        box.cox <- boxcoxfit(X, lambda=TRUE)
      } else {
        box.cox <- tryCatch({
          boxcoxfit(X, lambda=TRUE, lambda2=TRUE)
        }, error = function(e) {
          warning("BoxCox could not optimize lambda2 despite 0s. Using just lambda1.")
          boxcoxfit(X, lambda=TRUE)
        })
      }
  
      lambda1 <- box.cox$lambda[1]
      lambda2 <- box.cox$lambda[2]
      
      if (lambda1 == 0) {
        if (is.na(lambda2)) {
          Y <- log(X)
        } else {
          Y <- log(X + lambda2)
        }
      } else {
        if (is.na(lambda2)) {
          Y <- (X^lambda1 - 1)/lambda1
        } else {
          Y <- ((X+lambda2)^lambda1 - 1)/lambda1
        }
      }
      Y
    }, error = function(e) {
      stop("Box Cox did not converge. Reverting to simple min max scaling")
      X
    })
  } else {
    Y <- X
  }
  Y <- (Y - min(Y)) / (max(Y) - min(Y))
  return(Y)
}


scale.dt <- function(dt, draws, max_draw) {
  # scale each column in the data table using boxcox transform
  setkey(dt, indicator_id)
  if (draws) {
    scale.cols <- paste0("draw_", 0:max_draw)
  } else {
    scale.cols <- c("mean_val", "upper", "lower")
  }
  for (col in scale.cols) {
    dt[, (col):=scale.vector(get(col), scale), by=indicator_id]
    dt[[col]][dt$invert == 1] <- 1 - dt[[col]][dt$invert == 1]
  }
  dt[, c("scale", "invert") := NULL]
  return(dt)
}


get.indic.table <- function() {
  # get the indicator table
  if (Sys.info()[[1]] == "Windows") {
    indic_table <- fread("J:/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv")
  } else {
    indic_table <- fread("/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv")
  }
  return(indic_table)
}


read.dt <- function(sdg_version, draws, indic_table, max_draw=999) {
  # read in a data table with values to scale
  if (!draws) {
    path = paste0("J:/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/04_outputs/indicator_values/indicators_unscaled_", sdg_version, ".csv")
    dt0 <- fread(path)
    it <- subset(indic_table, select = c("indicator_id", "indicator_target", "scale", "invert"))
    dt0 <- merge(dt0, it, by=c("indicator_id"), all.x = TRUE)
    
    cols <- c(c("indicator_id", "location_id", "year_id", "indicator_target", "scale", "indvert"), c("mean_val", "upper", "lower"))
    dt0 <- subset(dt0, select=cols)
  } else {
    if (Sys.info()[[1]] == "Windows") {
      path = paste0("J:/temp/strUser/for_r_scaling_", sdg_version, ".csv")
    } else {
      path = "/ihme/scratch/projects/sdg/temp/for_r_scaling.csv"
    }
    dt0 <- fread(path)
    it <- subset(indic_table, select = c("indicator_id", "indicator_target"))
    dt0 <- merge(dt0, it, by=c("indicator_id"), all.x = TRUE)
    
    cols <- c(c("indicator_id", "location_id", "year_id", "indicator_target", "scale", "invert"), paste0("draw_", 0:max_draw))
    dt0 <- subset(dt0, select=cols)
  }
  
  return(dt0)
}


calc.composite.index <- function(dt, ids_in_comp, indic_id, draws, max_draw=999) {
  # calculate a composite index over each column in the datatable and append
  idx_dt <- copy(dt)
  idx_dt <- idx_dt[idx_dt$indicator_id %in% ids_in_comp]
  idx_dt[, c("indicator_id") := NULL]
  
  geom.mean <- function(X) {
    return(exp(sum(log(X)) / length(X)))
  }
  
  if (draws) {
    scale.cols <- paste0("draw_", 0:max_draw)
  } else {
    scale.cols <- c("mean_val", "upper", "lower")
  }
  
  for (col in scale.cols) {
    idx_dt[[col]][idx_dt[[col]] < 0.01] <- .01
  }
  print("Geom by target first")

  idx_dt <- idx_dt[, lapply(.SD, geom.mean), by=c('location_id', 'year_id', 'indicator_target'), .SDcols=scale.cols]
  idx_dt[, c("indicator_target") := NULL]
  print("Then geometric mean of those")
  idx_dt <- idx_dt[, lapply(.SD, geom.mean), by=c('location_id', 'year_id'), .SDcols=scale.cols]
  idx_dt[, c("indicator_id") := indic_id]
  return(idx_dt)
}

calc.means <- function(dt, max_draw=999) {
  # calculate mean, upper, lower and return
  sd.cols <- paste0("draw_", 0:max_draw)
  dt[, `:=`(mean_val = rowMeans(as.matrix(.SD), na.rm=T),
            upper = rowQuantiles(as.matrix(.SD), na.rm=T, probs=c(0.975)),
            lower = rowQuantiles(as.matrix(.SD), na.rm=T, probs=c(0.025))
            ), .SDcols=sd.cols]
  dt[, (sd.cols) := NULL]
  return(dt)
}

compile.dt <- function(dt, draws, indic_table, sdg_version, max_draw=999) {
  # calculate indices and collapse means together
  
  sdg_ids <- unique(indic_table[indic_table$indicator_status_id==1]$indicator_id)
  mdg_ids <- unique(indic_table[indic_table$indicator_status_id==1 & indic_table$mdg_agenda==1]$indicator_id)
  nonmdg_ids <- unique(indic_table[indic_table$indicator_status_id==1 & indic_table$mdg_agenda==0]$indicator_id)

  print("SDG Index")
  sdg_dt <- calc.composite.index(dt, sdg_ids, 1054, draws, max_draw=max_draw)
  print("MDG Index")
  mdg_dt <- calc.composite.index(dt, mdg_ids, 1055, draws, max_draw=max_draw)
  print("NON MDG Index")
  nonmdg_dt <- calc.composite.index(dt, nonmdg_ids, 1060, draws, max_draw=max_draw)
  
  dt[, c("indicator_target") := NULL]
  dt <- rbind(dt, sdg_dt)
  dt <- rbind(dt, mdg_dt)
  dt <- rbind(dt, nonmdg_dt)

  print("calculating means of draws")
  if (draws) {
    write.csv(dt, paste0("J:/temp/strUser/indicators_scaled_draws_", sdg_version, ".csv"), row.names=FALSE)
    #dt <- calc.means(dt, max_draw=max_draw)
  }
  
  # print("Calculating ranks")
  # rank_dt <- dt[dt$indicator_id==1054]
  # rank_dt[, rank:=rank(-mean_val, ties.method="first"), by=year_id]
  # rank_dt <- subset(rank_dt, select=c("location_id", "year_id", "rank"))
  
  # dt <- merge(dt, rank_dt, by=c("location_id", "year_id"))
  
  # print("Writing output")
  # write.csv(dt, paste0("J:/temp/strUser/", 
  #                      "indicators_scaled_", sdg_version, ".csv"), row.names=FALSE)
  return(dt)
}


draws = TRUE
sdg_version = 16
max_draw=999
indic_table <- get.indic.table()
dt <- read.dt(sdg_version, draws, indic_table, max_draw=max_draw)
dt <- scale.dt(dt, draws, max_draw=max_draw)
dt <- compile.dt(dt, draws, indic_table, sdg_version, max_draw=max_draw)
