## Plot exposure comparisons, GBD 2013 to GBD 2015


rm(list=ls()); library(data.table); library(foreign); library(ggplot2); library(RColorBrewer)
if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- "J:/"
  workdir <-  paste("/ihme/code/risk/",username,"/drugs_alcohol/",sep="")
  source("J:/Project/Mortality/shared/functions/get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  workdir <-  paste("/ihme/code/risk/",username,"/drugs_alcohol/",sep="")
  source("/home/j/Project/Mortality/shared/functions/get_locations.r")
}

locs <- get_locations(level="all")


d1 <- list()
for (i in c(1990,1995,2000,2005,2010,2013)) {
  d1[[paste0(i)]] <- fread(paste0(root,"/WORK/2013/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output/GBD2013/alc_data_",i,".csv"))
  d1[[paste0(i)]]$year <- i
}
d1 <- rbindlist(d1)
setnames(d1,"REGION","ihme_loc_id")
d1 <- merge(d1,locs[,c("ihme_loc_id","location_name","location_id")],by="ihme_loc_id",all.x=T)

d2 <- list()
for (i in c(1990,1995,2000,2005,2010,2015)) {
  d2[[paste0(i)]] <- fread(paste0("/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/postscale/alc_data_",i,".csv"))
  d2[[paste0(i)]]$year <- i
}
d2 <- rbindlist(d2)
d2 <- merge(d2,locs[,c("ihme_loc_id","location_name","location_id")],by="location_id",all.x=T)

d1$version <- "GBD 2013"
d2$version <- "GBD 2015"
d2 <- as.data.frame(d2)
d2 <- d2[,names(d2)[!names(d2) %in% c("X","Unnamed..0")]]

d <- rbind(d1,d2,use.names=T,fill=T)

write.csv(d,"/home/j/WORK/05_risk/risks/drugs_alcohol/diagnostics/compare_exposures.csv", row.names=F)
d <- as.data.frame(fread("/home/j/WORK/05_risk/risks/drugs_alcohol/diagnostics/compare_exposures.csv"))

## Makge graphs to look at differences

vars <- c("LIFETIME_ABSTAINERS","FORMER_DRINKERS","DRINKERS","PCA","VAR_PCA","BINGE_TIMES","BINGE_TIMES_SE","BINGERS","BINGERS_SE")

d$age_bin[d$AGE_CATEGORY==1] <- "15-34"
d$age_bin[d$AGE_CATEGORY==2] <- "35-59"
d$age_bin[d$AGE_CATEGORY==3] <- "60+"

d$sex_char[d$SEX == 1] <- "male"
d$sex_char[d$SEX == 2] <- "female"


d$sex_age <- paste0("sex ",d$sex_char,", age ",d$age_bin)
d$indic_2013[d$version == "GBD 2013"] <- 1
d <- d[order(d$indic_2013,d$ihme_loc_id,d$SEX,d$AGE_CATEGORY),]

## make versions a factor so colors work
d$version <- as.factor(d$version)
colors<-brewer.pal(9, "Set1")[c(1:2)]
colornames<-c("GBD 2015", "GBD 2013") 
names(colors)<-colornames
colScale <- scale_color_manual(name = "", values = colors)


for (i in vars) {
  pdf(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/diagnostics/GBD_comparison_",i,"_",Sys.Date(),".pdf"),height=8,width=10)
    for (loc in unique(d$location_id)) {
      cat(paste0(i," ",loc)); flush.console()
      tmp <- d[d$location_id == loc,]
      tmp$graph_var <- tmp[,paste0(i)]
      
      ymax <- max(1,tmp$graph_var)
      if (i == "BINGE_TIMES") ymax <- max(tmp$graph_var)
      ymin <- 0
      
      gg <- ggplot(data=tmp, aes(x = year, y = graph_var,group=version,colour=version)) + geom_point(size=1.4) + 
        facet_wrap(~ sex_age, nrow = 2,scales="fixed") +
        ggtitle(paste0(i," in ",unique(d$location_name[d$location_id == loc]), " ",unique(d$ihme_loc_id[d$location_id == loc]))) +
        ylab(paste0(i)) +
        colScale + 
        scale_y_continuous(limits=c(ymin,ymax))
      print(gg)
    }
  dev.off()
}



