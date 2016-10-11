## GRAB SURVEY SPECIFIC DATA AND INTERPOLATE RESULTS FROM SF-12 TO DW SPACE USING CROSSWALK SURVEY

library(foreign)
library(mgcv)

## Bring in Arguments (run from the main.do STATA do file)
path   <- commandArgs()[4]
survey <- commandArgs()[5]

path <- "strDir"
path_outliers <- "strDir"
survey <- "meps"

## Open the SF-12 data and X-WALK survey data created and appended in the 2_SURVEYNAME_prep.do file
data <- read.dta(paste(path,"/2a_",survey,"_crosswalk_key.dta",sep=""))
data_outliers <- read.dta(paste(path_outliers,"/2a_",survey,"_crosswalk_key.dta",sep=""))
outliers <- read.csv("strDir")
raw_data <- read.csv("strDir")

## sort
data <- data[order(data$sf),]

## set model
model <- loess(dw ~ sf, data=data, span=.88, control=loess.control(surface=c("direct")))
model_outliers <- loess(dw ~ sf, data=data_outliers, span=.88, control=loess.control(surface=c("direct")))

## fit model to prediction
dw_hat <- predict(model, newdata=data.frame(sf=data$predict))
dw_hat_outliers <- predict(model_outliers, newdata=data.frame(sf=data_outliers$predict))

## see what your prediction looks like
pdf('strPDFPath', width=11, height=8.5)
library(ggplot2)
estimates <- data.frame(x=data$predict, y=dw_hat)
estimates_outliers <- data.frame(x=data_outliers$predict, y=dw_hat_outliers)
p <- ggplot() +
        geom_line(data=estimates, aes(x=x, y=y), color="blue") +
        geom_line(data=estimates_outliers, aes(x=x, y=y), color="red") +
        scale_y_continuous(breaks=c(0,0.25,0.5,0.75,1.0), limits=c(0,1), expand=c(0,0)) +
        xlab("SF-12 Composite Score") +
        ylab("Disability Weight") +
        theme_bw()
plot(p)
dev.off()

## outsheet it
write.dta(data.frame(data,dw_hat),file=paste(path,"/2b_",survey,"_lowess_r_interpolation.dta",sep=""),convert.factors="string")
