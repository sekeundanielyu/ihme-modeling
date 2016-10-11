###########################################################
### Project: ubCov
### Purpose: Graph Tools
###########################################################

###################
### Setting up ####
###################
library(data.table)
library(ggplot2, lib.loc='/share/local/codem/anaconda/lib/R/library')
library(grid)
source('utility.r')

###################################################################
# Graphing Blocks
###################################################################


## Time series plot

plot_ts  <- function(input, output=NULL, location_id=NULL, type=NULL) {

	## Load
	if (class(input)[1] == "character") {
		if (grepl(".csv", input)) df <- fread(input)
		if (grepl(".rds", input)) df <- readRDS(input)
	} else if (grepl("data", class(input)[1])) {
		df <- input
	}

	## Checks
		## Check if required columns preent
		cols <- c("location_id", "year_id", "age_group_id", "sex_id")
		## Merge on level, region_id, parent_id
		check_cols <- c("level", "region_id", "parent_id", "location_name")
		merge_cols <- NULL
		for (col in check_cols) if (!(col %in% names(df))) merge_cols <- c(merge_cols, col)
		if (!is.null(merge_cols)) {
			geo <- get_location_hierarchy(41, china.fix=F)[, c("location_id", merge_cols), with=F]
			df <- merge(df, geo, by="location_id", all.x=T)
		}
		## Merge on age_group and sex names
		if (!("age_group_name" %in% names(df))) {
			ages <- get_ages()[,.(age_group_id, age_group_name)]
			df <- merge(df, ages, by="age_group_id", all.x=T)
		}
		if (!("sex" %in% names(df))) {
			df[sex_id==1, sex := "Male"]
			df[sex_id==2, sex := "Female"]
			df[sex_id==3, sex := "Both"]
		}

	## Setup
		## Possible objects to graph
		objs 	   <- c("data", "data_2013", "outlier", "prior",    "st",      "gpr_mean", "gpr_mean_unraked", "gpr_mean_2013")
		obj.names  <- c("Data", "Data 2013",  "Outlier", "Prior",   "ST", 	  "GPR",      "GPR Unraked", 	  "GPR 2013") 
		obj.colors <- c("black", "blue",  "black",   "#F2465A", "#1E90FF", "#218944",  "#218944",          "#756BB1")

		## Main Objects
		p.data <- geom_point(aes(y=data, x=year_id, color="Data"))
		p.data_ci <- geom_pointrange(aes(y=data, ymin=data-(1.96*sqrt(variance)), ymax=data+(1.96*sqrt(variance)), x=year_id), color="black")
		p.data_2013 <- geom_point(aes(y=data_2013, x=year_id, color="Data 2013"), shape=1)
		p.outlier <- geom_point(aes(y=outlier, x=year_id, color="Outlier"), shape=4)
		p.prior <- geom_line(aes(y=prior, x=year_id, color="Prior")) 
		p.st <- geom_line(aes(y=st, x=year_id, color="ST")) 
		p.gpr_mean <- geom_line(aes(y=gpr_mean, x=year_id, color="GPR"))
		p.gpr_ci <- geom_ribbon(aes(ymin=gpr_lower, ymax=gpr_upper, x=year_id), fill="#218944", alpha=0.2)
		
		## Other
		p.gpr_mean_unraked <- geom_line(aes(y=gpr_mean_unraked, x=year_id, color="GPR Unraked")) 
		p.gpr_mean_2013 <- geom_line(aes(y=gpr_mean_2013, x=year_id, color="GPR 2013"))
		p.gpr_ci_2013 <- geom_ribbon(aes(ymin=gpr_lower_2013, ymax=gpr_upper_2013, x=year_id), fill="#756BB1", alpha=0.2)

		## Locations names
		locs <- get_location_hierarchy(74, china.fix=F)[, .(location_id, location_name, ihme_loc_id, region_id, level, parent_id)]

	## Settings
		## Set objects to graph
		gobjs <- NULL
		## If didn't specify, take everything that is in the df
		if (is.null(type)) for (obj in objs) if (obj != "data") if (obj %in% names(df)) gobjs <- c(gobjs, obj)
		## Else
		if (!is.null(type)) for (obj in type) if (obj %in% names(df)) gobjs <- c(gobjs, obj)
		if ("gpr_mean" %in% gobjs) gobjs <- c(gobjs, "gpr_ci")
		#if ("gpr_mean_2013" %in% gobjs) gobjs <- c(gobjs, "gpr_ci_2013")

		## Set locations
		if (is.null(location_id))  location_id <- unique(df$location_id)

		## Set axis range
		if ("data" %in% names(df)) {
			y.min <- quantile(df[!is.na(data),data], 0.001, na.rm=T)
			y.max <- quantile(df[!is.na(data),data], 0.999, na.rm=T)
		} else {
			y.min <- quantile(df[!is.na(gpr_mean),gpr_mean], 0.001, na.rm=T)
			y.max <- quantile(df[!is.na(gpr_mean),gpr_mean], 0.999, na.rm=T)
		}
		x.min <- min(df[,year_id])
		x.max <- max(df[,year_id])

	## Output
	if (!is.null(output)) pdf(paste0(output), w=15, h=10)

	## Build Graph
	for (loc in location_id) {
	for (sexy in unique(df$sex)) {

		## Get location name, ihme_loc_id
		loc.name <- locs[location_id==loc, location_name]
		loc.iso3 <- locs[location_id==loc, ihme_loc_id]
		loc.region <- locs[location_id==loc, region_id]
		loc.level <- locs[location_id==loc, level]
		loc.parent <- locs[location_id==loc, parent_id]

		## Data count
		if ("data" %in% names(df)) {
			count <- nrow(df[location_id==loc & sex==sexy & !is.na(data),])
			r.count <- nrow(df[region_id==loc.region & sex==sexy & !is.na(data),])		
		} else {
			count <- 0
			r.count <- 0
		}

		## Graph
		p <- ggplot(df[location_id==loc & sex==sexy,]) 
			## Graph objects
			for (obj in gobjs)  p <- p + get(paste0("p.", obj))
			## Region data
			if (r.count > 0) p <- p + geom_point(data=df[region_id==loc.region & sex==sexy & location_id != loc,], aes(y=data, x=year_id), color="grey60", alpha=0.5)
			## Data
			if (count > 0) {
				p <- p + p.data
				p <- p + p.data_ci
			}
			## Age/sex facet
			p <- p + facet_wrap(~age_group_name, ncol=4) + 
			## Colors
			scale_colour_manual(values=setNames(obj.colors, obj.names)) +
			## Appearance
			xlab("Year") + 
			coord_cartesian(ylim=c(y.min, y.max), xlim=c(x.min, x.max)) + 
			theme_bw()+ 
		    theme(axis.title=element_text(),
		           	 plot.title=element_text(face="bold",size=18),
		           	 strip.text=element_text(size=12, face ="bold"),
		           	 strip.background=element_blank(),
		           	 axis.text.x = element_text(size = 9),
		           	 panel.margin=unit(1,"lines"),
		           	 legend.position = "bottom",
		           	 legend.title = element_blank(),
		           	 legend.background = element_blank(),
		           	 legend.key = element_blank()
		           	 )+
		    ## Title
		    ggtitle(paste0(loc.name, " (", loc.iso3, "), ", sexy))

		## Output
		if (is.null(output)) return(p)
		if (!is.null(output)) { 
			print(p)
			print(paste0("Graph complete: ", loc.iso3))
		}
	}
	}	 

	## Finish
	if (!is.null(output)) dev.off()	

}




