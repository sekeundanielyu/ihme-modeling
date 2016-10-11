
####################
## Make parameter plots
####################


rm(list=ls())
library(foreign); library(lme4); library(RColorBrewer)

if (Sys.info()[1] == "Linux") root <- "" else root <- ""
setwd(paste(root, "", sep=""))

## selected parameters
params <- read.csv("selected_parameters.txt")

params$mse <- format(round(params$mse, 5), nsmall=5, digits=5)
params$version <- factor(paste(params$scale, "; ", params$amp2x, sep=""),
                            levels=paste(rep(sort(unique(params$scale)), each=5), "; ", rep(sort(unique(params$amp2x)), 4), sep=""))

colors <- brewer.pal(5, "Set1")
symbols <- 21:25

pdf(paste("parameter_selection_by_gbd_region_",Sys.Date(),".pdf",sep = ""), width=10, height=7)
print(xyplot(are ~ coverage|gbd_region, groups=version, data=params,
             selected.loss=params$best,
             layout=c(1,1), scales=list(alternate=F,relation="free"), type=c("p","g"),
             panel = panel.superpose,
             panel.groups = function(x,y,subscripts,selected.loss,...) {
               panel.xyplot(x,y,...)
               panel.xyplot(x[selected.loss[subscripts]==1], y[selected.loss[subscripts]==1], pch=0, cex=3, col="black")
             },
             par.settings=list(superpose.symbol=list(col=rep(colors, each=5),
                                                     fill=rep(colors, each=5),
                                                     pch=rep(symbols,5),
                                                     cex=1.2)),
             auto.key=list(space="right")))
dev.off()