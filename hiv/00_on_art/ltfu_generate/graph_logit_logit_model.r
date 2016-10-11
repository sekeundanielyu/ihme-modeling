# Allen Roberts
# February 2014
# Graph LTFU correction factor regression scatter

# Set up
rm(list=ls())
library(ggplot2)
library(RColorBrewer)
library(boot)
graph_dir <- "J:\WORK\04_epi\01_database\02_data\hiv\on_art\graphs\ltfu_analysis"
data_dir <- "J:\WORK\04_epi\01_database\02_data\hiv\on_art\data\ltfu_analysis"

# Overall plot theme to have white background
theme_set(theme_bw())

# Bring in data
data <- read.csv(paste0(data_dir,"/ltfu_scatter_for_graphing_in_r.csv"))
data$logit_prop_traced_dead <- logit(data$prop_traced_dead)
data$logit_prop_ltfu <- logit(data$prop_ltfu)

# Regress and back-transform predictions
logit.logit <- lm(logit_prop_traced_dead ~ logit_prop_ltfu, data=data)
pred.data <- data.frame(logit_prop_ltfu = seq(-5,1,0.05))
pred.data$logit_prop_traced_dead <- predict(logit.logit, pred.data)
pred.data$prop_traced_dead <- inv.logit(pred.data$logit_prop_traced_dead)
pred.data$prop_ltfu <- inv.logit(pred.data$logit_prop_ltfu)

# Regress and back-transform predictions
lin <- lm(prop_traced_dead ~ prop_ltfu, data=data)
pred.data.lin <- data.frame(prop_ltfu = seq(0, 1, 0.05))
pred.data.lin$prop_traced_dead <- predict(lin, pred.data.lin)

# graph.data <- subset(data, select=c(prop_traced_dead, prop_ltfu))
# graph.data$model_traced_dead <- pred.data$prop_traced_dead
# graph.data$model_ltfu <- pred.data$prop_ltfu

# Graph
pdf(file = paste0(graph_dir,"/logit_logit_model.pdf"), height = 5, width = 5)
p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
  geom_point() +
  geom_line(data=pred.data) +
  scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
  xlab("Proportion lost to follow up") +
  ylab("Proportion dead of those lost to follow up")
print(p)
dev.off()

pdf(file =  paste0(graph_dir,"/linear_model.pdf"), height = 5, width = 5)
p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
  geom_point() +
  geom_line(data=pred.data.lin) +
  scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
  xlab("Proportion lost to follow up") +
  ylab("Proportion dead of those lost to follow up")
print(p)
dev.off()

pdf(file = paste0(graph_dir,"/ltfu_model_compare.pdf"), height = 5, width = 5)
p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
  geom_point() +
  geom_line(data=pred.data) +
  scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
  xlab("Proportion lost to follow up") +
  ylab("Proportion dead of those lost to follow up")
print(p)
p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
  geom_point() +
  geom_line(data=pred.data.lin) +
  scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
  xlab("Proportion lost to follow up") +
  ylab("Proportion dead of those lost to follow up")
print(p)
dev.off()

## Weighted models

# Regress and back-transform predictions
wt.logit.logit <- lm(logit_prop_traced_dead ~ logit_prop_ltfu, data=data, weights=data$num_traced)
wt.pred.data <- data.frame(wt.logit_prop_ltfu = seq(-5,1,0.05))
wt.pred.data$logit_prop_traced_dead <- predict(wt.logit.logit, pred.data)
wt.pred.data$prop_traced_dead <- inv.logit(pred.data$logit_prop_traced_dead)
wt.pred.data$prop_ltfu <- inv.logit(pred.data$logit_prop_ltfu)

# Regress and back-transform predictions
wt.lin <- lm(prop_traced_dead ~ prop_ltfu, data=data, weights=data$num_traced)
wt.pred.data.lin <- data.frame(prop_ltfu = seq(0, 1, 0.05))
wt.pred.data.lin$prop_traced_dead <- predict(wt.lin, pred.data.lin)

# graph.data <- subset(data, select=c(prop_traced_dead, prop_ltfu))
# graph.data$model_traced_dead <- pred.data$prop_traced_dead
# graph.data$model_ltfu <- pred.data$prop_ltfu

# # Graph
# pdf(file = "./logit_logit_model.pdf", height = 5, width = 5)
# p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
#   geom_point() +
#   geom_line(data=wt.pred.data) +
#   scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
#   xlab("Proportion lost to follow up") +
#   ylab("Proportion dead of those lost to follow up")
# print(p)
# dev.off()
# 
# pdf(file = "./linear_model.pdf", height = 5, width = 5)
# p <- ggplot(data, aes(prop_ltfu, prop_traced_dead)) +
#   geom_point() +
#   geom_line(data=wt.pred.data.lin) +
#   scale_x_continuous(limits = c(0,1)) + scale_y_continuous(limits = c(0,1)) +
#   xlab("Proportion lost to follow up") +
#   ylab("Proportion dead of those lost to follow up")
# print(p)
# dev.off()
