require(ggplot2)

data <- read.csv("J:/WORK/04_epi/03_outputs/01_code/02_dw/01_code/ckd_stage5_dws/combined_dw_draws.csv")
data[data$sex==1, "sex_lab"] <- "Male"
data[data$sex==2, "sex_lab"] <- "Female"
data$sex_lab <- "Both sexes"

p <- ggplot(data, aes(x=value)) + geom_histogram() + facet_grid( . ~ sex_lab) + ggtitle("Combined DW : CKD4 + Terminal") + xlab("DW value")
plot(p)
ggsave("J:/WORK/04_epi/03_outputs/01_code/02_dw/01_code/ckd_stage5_dws/ckd4_term_dw_hist.pdf", p)