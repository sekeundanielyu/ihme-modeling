require(plyr)
require(ggplot2)
require(data.table)
require(stringr)

args <- commandArgs(trailingOnly = TRUE)
como_v <- if (is.na(args[1])) 94 else args[1]
lid <- if (is.na(args[2])) 44634 else args[2]

lnames <- list("1"="Global",
               "44634"="High-middle SDI",
               "44635"="High SDI",
               "44636"="Low-middle SDI",
               "44637"="Low SDI",
               "44639"="Middle SDI")

###################################
## PLOT DW COUNTS
###################################
for (lid in c(1, 44634, 44635, 44636, 44637, 44639)){
    for (y in c(2015)) {
        dist_data <- fread(paste0("/ihme/centralcomp/como/", como_v, "/pyramids/dws_", lid, ".csv"))
        dist_data <- dist_data[year_id == y]
        dist_data[bin_lower<0, "dw_range":="No disability"]
        dist_data[bin_lower>=0 & bin_lower<0.01, "dw_range":="Very mild"]
        dist_data[bin_lower>=0.01 & bin_lower<0.05, "dw_range":="Mild"]
        dist_data[bin_lower>=0.05 & bin_lower<0.1, "dw_range":="Moderate"]
        dist_data[bin_lower>=0.1 & bin_lower<0.3, "dw_range":="Severe"]
        dist_data[bin_lower>=0.3, "dw_range":="Very severe"]

        dist_data[age_group_id <= 5, age_group_id:=1]
        range_counts <- dist_data[,
                                  list(scaled_draw_mean=sum(scaled_draw_mean)),
                                  c("year_id", "age_group_id", "sex_id", "dw_range")]
        range_counts[age_group_id==1, age_group:="0 to 4 yrs"]
        range_counts[age_group_id==6, age_group:="5 to 9 yrs"]
        range_counts[age_group_id==7, age_group:="10 to 14 yrs"]
        range_counts[age_group_id==8, age_group:="15 to 19 yrs"]
        range_counts[age_group_id==9, age_group:="20 to 24 yrs"]
        range_counts[age_group_id==10, age_group:="25 to 29 yrs"]
        range_counts[age_group_id==11, age_group:="30 to 34 yrs"]
        range_counts[age_group_id==12, age_group:="35 to 39 yrs"]
        range_counts[age_group_id==13, age_group:="40 to 44 yrs"]
        range_counts[age_group_id==14, age_group:="45 to 49 yrs"]
        range_counts[age_group_id==15, age_group:="50 to 54 yrs"]
        range_counts[age_group_id==16, age_group:="55 to 59 yrs"]
        range_counts[age_group_id==17, age_group:="60 to 64 yrs"]
        range_counts[age_group_id==18, age_group:="65 to 69 yrs"]
        range_counts[age_group_id==19, age_group:="70 to 74 yrs"]
        range_counts[age_group_id==20, age_group:="75 to 79 yrs"]
        range_counts[age_group_id==21, age_group:="80+ yrs"]
        range_counts$age_group_id <- as.factor(range_counts$age_group_id)
        range_counts$age_group <- factor(range_counts$age_group,
                                         levels=c("0 to 4 yrs","5 to 9 yrs","10 to 14 yrs","15 to 19 yrs","20 to 24 yrs","25 to 29 yrs","30 to 34 yrs","35 to 39 yrs","40 to 44 yrs","45 to 49 yrs","50 to 54 yrs","55 to 59 yrs","60 to 64 yrs","65 to 69 yrs","70 to 74 yrs","75 to 79 yrs","80+ yrs"))

        range_counts$dw_range <- factor(range_counts$dw_range,
                                        levels=c("No disability",
                                                 "Very mild",
                                                 "Mild",
                                                 "Moderate",
                                                 "Severe",
                                                 "Very severe"))

        range_counts$num_people <- range_counts$scaled_draw_mean / 1e6
        lim <- max(range_counts[,sum(num_people),
                   c("age_group_id", "sex_id", "year_id")]$V1)
        breaks <- round(seq(-lim, lim, length.out=10), 0)
        labels <- abs(breaks)
        p <- ggplot() +
                geom_bar(data=subset(range_counts, sex_id==1),
                         aes(x=age_group,
                             y=num_people,
                             fill=dw_range,
                             order=desc(dw_range)),
                         stat="identity") +
                geom_bar(data=subset(range_counts, sex_id==2),
                         aes(x=age_group,
                             y=-num_people,
                             fill=dw_range,
                             order=desc(dw_range)),
                         stat="identity") +
                scale_y_continuous(
                                   limits=c(-lim, lim),
                                   breaks=breaks,
                                   labels=labels) +
                scale_fill_brewer(palette="Spectral", name="Disability level", direction=-1) +
                ylab("Population (millions)") +
                xlab("Age") +
                theme_bw() +
                theme(
                      plot.caption=element_text(size=6, hjust=0, margin=margin(t=10), face="italic"),
                      plot.title=element_text(size=10),
                      plot.subtitle=element_text(size=8, face="italic")) +
                ggtitle(str_wrap("Figure 5a-e. Population pyramids with the number of individuals, by age and sex, grouped by severity of their disability weight (DW) for all comorbid conditions combined into no disability, very mild disability (DW 0 to 0.01), mild disability (DW 0.01 to 0.05), moderate disability (DW 0.05 to 0.1), severe disability (DW 0.1 to 0.3), and very severe disability (DW greater than 0.3) for geographies for five quintiles of Socio-Demographic Index in 2015", width=70), subtitle=lnames[[as.character(lid)]]) +
                geom_hline(yintercept=0, color="gray90") +
                annotate("text", x=17, y=-.9*lim, label = "Female") +
                annotate("text", x=17, y=.9*lim, label = "Male") +
                coord_flip() +
                labs(caption = str_wrap("Disability weights are combined multiplicatively as 1-(1-DW1)(1- DW2)…(1-DWn) for n comorbid sequelae. Socio-Demographic Index (SDI) is calculated for each geography as a function of lag dependent income per capita, average educational attainment in the population over age 15, and the total fertility rate. SDI units are interpretable; a zero represents the lowest level of income per capita, educational attainment, and highest TFR observed from 1980 to 2015 and a one represents the highest income per capita, educational attainment and lowest TFR observed in the same period. Cutoffs on the SDI scale for the quintiles have been selected based on examining the entire distribution of geographies, 1980-2015.", width=110))
        plot(p)
        ggsave(paste0("pyramid_", lid, "_", y, ".pdf"), p)
        ggsave(paste0("strDir/como_v",
                      como_v,
                      "/poppyr_by_dw_",
                      lid,
                      "_",
                      y,
                      ".pdf"), p)
    }
}
