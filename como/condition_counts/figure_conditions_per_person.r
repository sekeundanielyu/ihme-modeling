# Description: Plot condition pyramids for non-fatal paper

require(plyr)
require(ggplot2)
require(data.table)

args <- commandArgs(trailingOnly = TRUE)
como.version <- if (is.na(args[1])) 22 else args[1]
dn.version <- if (is.na(args[2])) 42 else args[2]
location <- if (is.na(args[3])) "USA" else args[3]

out_directory <- paste0("/home/j/WORK/04_epi/03_outputs/01_code/01_como/dev/condition_counts/v", como.version,"/plots")

###################################
## PLOT CONDITION COUNTS
###################################
filename <- paste0(out_directory,"/",location, "_como_v",como.version,"_daly_v",dn.version,".pdf")
pdf(filename, width=14, height=11)

###################################
## GROUP-SPECIFIC SETTINGS
###################################

count_data <- read.csv(paste0("/home/j/WORK/04_epi/03_outputs/01_code/01_como/dev/condition_counts/v",como.version,"/locations/",location,"_cond_count_yas.csv"))

location_name <- unique(count_data$location_name)

count_data <- data.table(count_data)
count_data[num_diseases==0, "num_conditions":="0"]
count_data[num_diseases==1, "num_conditions":="1"]
count_data[num_diseases==2, "num_conditions":="2"]
count_data[num_diseases==3, "num_conditions":="3"]
count_data[num_diseases==4, "num_conditions":="4"]
count_data[num_diseases==5, "num_conditions":="5"]
count_data[num_diseases==6, "num_conditions":="6"]
count_data[num_diseases==7, "num_conditions":="7"]
count_data[num_diseases==8, "num_conditions":="8"]
count_data[num_diseases==9, "num_conditions":="9"]
count_data[num_diseases>=10, "num_conditions":="10+"]

count_data[age<5, age_group:=0]
count_data[age>=5, age_group:=age]
count_data$age <- count_data$age_group
count_data$age_group <- as.character(count_data$age_group)

# Relabel age groups
count_data[age==0, age_group:="0 to 4 yrs"]
count_data[age==5, age_group:="5 to 9 yrs"]
count_data[age==10, age_group:="10 to 14 yrs"]
count_data[age==15, age_group:="15 to 19 yrs"]
count_data[age==20, age_group:="20 to 24 yrs"]
count_data[age==25, age_group:="25 to 29 yrs"]
count_data[age==30, age_group:="30 to 34 yrs"]
count_data[age==35, age_group:="35 to 39 yrs"]
count_data[age==40, age_group:="40 to 44 yrs"]
count_data[age==45, age_group:="45 to 49 yrs"]
count_data[age==50, age_group:="50 to 54 yrs"]
count_data[age==55, age_group:="55 to 59 yrs"]
count_data[age==60, age_group:="60 to 64 yrs"]
count_data[age==65, age_group:="65 to 69 yrs"]
count_data[age==70, age_group:="70 to 74 yrs"]
count_data[age==75, age_group:="75 to 79 yrs"]
count_data[age==80, age_group:="80+ yrs"]

range_counts <- count_data[, list(scaled_people=sum(scaled_people)), c("year","age_group","sex","num_conditions")]
range_counts$age_group <- factor(range_counts$age_group,
                                 levels=c("0 to 4 yrs","5 to 9 yrs","10 to 14 yrs","15 to 19 yrs","20 to 24 yrs","25 to 29 yrs","30 to 34 yrs","35 to 39 yrs","40 to 44 yrs","45 to 49 yrs","50 to 54 yrs","55 to 59 yrs","60 to 64 yrs","65 to 69 yrs","70 to 74 yrs","75 to 79 yrs","80+ yrs"))
range_counts$num_conditions <- factor(range_counts$num_conditions,
                                levels=c("0","1","2","3","4","5","6","7","8","9","10+"))

if (max(range_counts$scaled_people) > 1e6) {
    range_counts$scaled_people <- range_counts$scaled_people / 1e6
    ylab <- "Population (millions)"
} else {
    range_counts$scaled_people <- range_counts$scaled_people / 1e5
    ylab <- "Population (x100,000)"
}

lim <- max(range_counts[,sum(scaled_people),c("age_group","sex","year")]$V1)
breaks <- round(seq(-lim,lim,length.out=20),1)
labels <- abs(breaks)

for (y in c(1990, 2013)) {

    plot_data <- range_counts[year==y]
    title <- paste("Population pyramid for",location_name,"stratified by the number of conditions they experience in",y)

    p <- ggplot() +
            geom_bar(data=subset(plot_data,sex=="male"), aes(x=age_group, y=scaled_people, fill=num_conditions, order=desc(num_conditions)), stat="identity") +
            geom_bar(data=subset(plot_data,sex=="female"), aes(x=age_group, y=-scaled_people, fill=num_conditions, order=desc(num_conditions)), stat="identity") +
            scale_y_continuous(limits=c(-lim, lim), breaks=breaks, labels=labels) +
            scale_fill_brewer(palette="Spectral", name="Number of conditions") +
            ylab(ylab) +
            xlab("Age") +
            ggtitle(title) +
            geom_hline(yintercept=0, color="gray90") +
            coord_flip() +
            theme_bw() +
            theme(plot.title=element_text(vjust=2), axis.title.y=element_text(vjust=0.2), axis.title.x=element_text(vjust=0)) +
            annotate("text", x=17, y=-.875*lim, label = "Female") +
            annotate("text", x=17, y=.875*lim, label = "Male")

    plot(p)
}

graphics.off()
