###########################################################
### Project: ubCov
### Purpose: Produce Graphs
###########################################################

###################
### Setting up ####
###################
args <- commandArgs(trailingOnly = TRUE)
central_root <- args[1]
graph <- args[2]
input <- args[3]
output <- args[4]
location_id <- args[5]

setwd(central_root)
source('graph.r')
source('utility.r')

###################################################################
# Run Graphs
###################################################################

if (graph == "plot_ts") plot_ts(input=input, output=output, location_id=location_id)

if (graph == "plot_apc") plot_apc(input=input, output=output, location_id=location_id)

if (graph == "append") append_pdf(files=input, output=output)






