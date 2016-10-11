library(data.table)
library(reshape2)
library(ggplot2)
library(foreign)

# Fill single ages
# Convenient for data.table
extend.ages <- function(a.vec) {
  return(min(a.vec):max(a.vec))
}

# Get arguments
args <- commandArgs(trailingOnly = TRUE)
# Location
loc <- args[1]
# Run folder name
run.dir <- args[2]
# Adjusted incidence output directory
out.dir <- args[3]
start.time <- proc.time()

# Map of proprietary Spectrum location IDs to GBD IDs
loc.map <- fread('/strPath/GBD_2015_countries.csv')
loc.map[,spec.loc:=iso3]
loc.map[subnat_id != "", spec.loc:=paste0(spec.loc,'_',subnat_id)]

gbd.locs <- loc.map[spec.loc == loc, unique(ihme_loc_id)]
spec.locs <- loc.map[ihme_loc_id %in% gbd.locs, unique(spec.loc)]

# Location of Spectrum data to be adjusted
in.dir <- paste0('/strPath/',run.dir,'/compiled/stage_1')
setwd(in.dir)

# Read in all necessary locations for current location
# (Subnationals if adjusting nationally, for instance)
inc.data <- data.table()
for (tmp.loc in spec.locs) {
	tmp.inc.data <- fread(paste0(tmp.loc,'_ART_data.csv'))
	tmp.inc.data[,total.pop := pop_neg+pop_lt200+pop_200to350+pop_gt350+pop_art]
	tmp.inc.data <- tmp.inc.data[age >= 15,.(run_num, year, age, sex, new_hiv, suscept_pop, hiv_deaths, total.pop)]
	if (tmp.loc != loc) {
		tmp.inc.data[,new_hiv := 0]
		tmp.inc.data[,suscept_pop := 0]
	}
	tmp.inc.data[,loc := tmp.loc]
	inc.data <- rbind(inc.data, tmp.inc.data)
}
# Aggregate to GBD location
inc.data <- inc.data[,.(new_hiv=sum(new_hiv), suscept_pop=sum(suscept_pop), hiv_deaths=sum(hiv_deaths), total.pop=sum(total.pop)), by=.(run_num, year, age, sex)]

# Get number of draws in input
n.draws <- length(inc.data[,unique(run_num)])

# Get Spectrum population for use in population scaling
spec.pop.dt <- inc.data[,.(total.pop=mean(total.pop)), by=.(year, age, sex)]

# Create structure for single age data
single.age.structure <- inc.data[,.(single.age = extend.ages(age)),by=.(year,sex,run_num)]
single.age.structure[,age:=single.age-(single.age%%5)]

# Replicate observations for single-ages and divide HIV deaths by five
merged.inc.data <- merge(inc.data, single.age.structure, by=c('year', 'age', 'sex', 'run_num'), all.y=T)
merged.inc.data[,single.d := hiv_deaths/5]
merged.inc.data[age==80, single.d := hiv_deaths]

# Divide new infections by five
merged.inc.data[,single.cases := new_hiv/5]
merged.inc.data[age==80, single.cases := new_hiv]

# Divide susceptible population by five
merged.inc.data[,single.pop := suscept_pop/5]
merged.inc.data[age==80, single.pop := suscept_pop]

# Convert new infections to wide format (year, age, and sex long, draws wide)
wide.inc.data <- data.table(dcast(merged.inc.data[,.(year, single.age, sex, run_num, single.cases)], year+single.age+sex~run_num, value.var=c('single.cases')))
setnames(wide.inc.data, as.character(1:n.draws), paste0('single.cases_',1:n.draws))

# Convert susceptible population to wide format
long.pop.data <- merged.inc.data[single.age>=15 & single.age < 50,.(single.pop = sum(single.pop)), by=.(year, run_num)]
wide.pop.data <- data.table(dcast(long.pop.data[,.(year, run_num, single.pop)], year~run_num, value.var=c('single.pop')))
setnames(wide.pop.data, as.character(1:n.draws), paste0('single.pop_',1:n.draws))

# Get GBD population
pop.data <- data.table(read.dta('/strPath/population_gbd2015.dta'))
pop.data <- pop.data[sex != 'both' & (age_group_id >= 2 & age_group_id <= 21),
                     .(ihme_loc_id, year, sex, sex_id, age_group_id, age_group_name, pop, location_id)]
pop.data[age_group_id < 5, age_group_id := 5]
pop.data[,age := 5*(age_group_id-5)]
pop.data[,year_id := year]

# Get GPR mortality results 
cod.data <- fread('/strPath/spectrum_gpr_results.csv')
cod.pop.merged <- merge(cod.data,pop.data, by=c('location_id', 'year_id','age_group_id','sex_id'))

# Get counts of GPR deaths
cod.pop.merged[,deaths := pop*gpr_mean/100]

# Aggregate counts to same location as Spectrum reuslts and recalculate rate
cod.pop.collapsed <- cod.pop.merged[ihme_loc_id %in% gbd.locs,.(deaths=sum(deaths), pop=sum(pop)), by=.(ihme_loc_id, year, age, sex)]
cod.pop.collapsed[, mort:=deaths/pop]


# Calculate deaths with _Spectrum_ population, not GBD
# Accounts for the fact that we only keep Spectrum rates
# Works surprisingly well
spec.cod.dt <- merge(spec.pop.dt, cod.pop.collapsed, by=c('year', 'age', 'sex'))
spec.cod.dt[,hiv_deaths := total.pop*mort]

# Get to correct location
cod.data <- spec.cod.dt[ihme_loc_id %in% gbd.locs,.(deaths=sum(hiv_deaths)), by=.(year, age, sex)]
# Get single-age structure for GPR data
single.age.structure <- cod.data[,.(single.age = extend.ages(age)),by=.(year,sex)]
single.age.structure[,age:=single.age-(single.age%%5)]

# Convert GPR deaths to single ages
merged.cod.data <- merge(cod.data, single.age.structure, by=c('year', 'age', 'sex'))
merged.cod.data[,single.cod := deaths/5]
merged.cod.data[age==80, single.cod := deaths]

# Get year extent of CoD data
cod.years <- min(cod.data[,year]):max(cod.data[,year])

# Identify years to use in adjustment
obs.years <- pmax(min(cod.years), 1990):max(cod.years)

# Merge both death datasets together and calculate the ratio
merged.deaths <- merge(merged.cod.data, merged.inc.data[year %in% cod.years], by=c('year','single.age','sex'))
merged.deaths <- merged.deaths[year %in% obs.years]
merged.deaths[,r:=single.cod/single.d]
merged.deaths[single.d==0,r:=0]

# Convert ratios to wide format (wide on draws)
wide.deaths <- data.table(dcast(merged.deaths[,.(year, single.age, sex, r, run_num)], year+single.age+sex ~ run_num, value.var=c('r')))
setnames(wide.deaths, as.character(1:n.draws), paste0('r_',1:n.draws))

setwd('/strPath/stage_1')

reshaped.data <- data.table()

# Get data from duration Spectrum run
for (tmp.loc in spec.locs) {	
	tmp.data <- fread(paste0(loc,'_ART_deaths_1.csv'))
	in.data <- melt(tmp.data, id.vars=c('year','age','sex'))
	in.data[, loc := tmp.loc]
	reshaped.data <- rbind(reshaped.data, in.data)
}

# Aggregate to correct location
reshaped.data <- reshaped.data[year %in% obs.years,.(value=sum(value)), by=.(year, age, sex, variable)]

reshaped.data[,variable:=as.character(variable)]


# Identify years of infection
split.names <- t(sapply(strsplit(reshaped.data[,variable], '_'), function(x) {c(x[1],x[2])}))
reshaped.data[,metric := split.names[,1]]
reshaped.data[,inf_year := as.integer(split.names[,2])]

# Restrict to deaths
reshaped.data <- reshaped.data[metric=='d']
reshaped.data[,variable:=NULL]
reshaped.data[,inf_year:=as.numeric(inf_year)]
setnames(reshaped.data, 'age', 'single.age')

# Calculate time since infection and age at infection for a given year-age-infection combination

## YEAR: chronological year
## INF_YEAR: year of infection
## AGE: current age
reshaped.data[,inf.dist := year-inf_year]
reshaped.data[,inf.age := single.age - inf.dist]

# Restrict to observation years
reshaped.data <- reshaped.data[year %in% cod.years]

# Calculate total HIV deaths for ech infection year-age-sex cohort and merge back on to full dataset
cohort.d <- reshaped.data[,.(total.d = sum(value)), by=.(inf_year, inf.age, sex)]
reshaped.data <- merge(reshaped.data, cohort.d, by=c('inf_year', 'inf.age', 'sex'))

# Calculate rho, the cohort-specifc share of observed HIV deaths that occur in a particular year
# Used to weight "r" calculated previously
reshaped.data[,rho := value/total.d]
reshaped.data[total.d == 0, rho := 0]

# Identify last year
max.year <- reshaped.data[,max(inf_year)]

# Convert rho to wide format by cohort
wide.rho.data <- merge(reshaped.data,wide.deaths, by=c('year', 'single.age', 'sex'))
wide.combined.data <- wide.rho.data[,.(year, single.age, sex, inf_year, inf.age)]
alloc.col(wide.combined.data,1005)

# Multiply each "r" by the appropriate "rho"
r.cols <- paste0('r_', 1:n.draws)
for (i in 1:n.draws) {
  set(wide.combined.data,j=paste0('combined.r_',i),value=wide.rho.data[[paste0('r_',i)]] * wide.rho.data[['rho']])
}

# Aggregate weighted r's
combined.r.dt <- wide.combined.data[,lapply(.SD, sum, na.rm=T),by=.(inf_year, inf.age, sex), .SDcols=paste0('combined.r_',1:n.draws)]

# Once we aggregate we can think of inf_year and inf_age as
# chronological year and age because we only have one observation per cohort
setnames(combined.r.dt, c('inf_year', 'inf.age'), c('year', 'single.age'))

# Restrict to appropriate years
combined.r.dt <- combined.r.dt[year < max.year]
# Extend second to last year to adjust actual last year
penult.r <- combined.r.dt[year==max.year-1]
penult.r[,year:=max.year]
combined.r.dt <- rbind(combined.r.dt, penult.r)

# Merge adjusted r and original new cases from Spectrum
adj.data <- merge(wide.inc.data, combined.r.dt, by=c('year', 'single.age', 'sex'))

# Adjust cohort-specific incidence using adjusted r
alloc.col(adj.data, 3003)
for (i in 1:n.draws) {
  set(adj.data,j=paste0('adj.cases_',i),value=adj.data[[paste0('single.cases_',i)]]*adj.data[[paste0('combined.r_',i)]])
}

# Aggregate to appropriate ages and across sex
agg.data <- adj.data[single.age<50,lapply(.SD, sum, na.rm=T),by=.(year), .SDcols=paste0('adj.cases_',1:n.draws)]
agg.data <- merge(agg.data, wide.pop.data, by=c('year'))
out.data <- agg.data[,.(year)]
# Convert to rate per susceptible person and multiply by 100
alloc.col(out.data, 1001)
for (i in 1:n.draws) {
  set(out.data,j=paste0('draw',i),value=100*agg.data[[paste0('adj.cases_',i)]]/agg.data[[paste0('single.pop_',i)]])
}
print(proc.time()-start.time)

write.csv(out.data, paste0('/strPath/',loc,'_SPU_inc_draws.csv'), row.names=F)

# Calculate net adjustment ratio for use in places without VR
orig.inc <- inc.data[age>=15 & age<50, .(new_hiv=sum(new_hiv), suscept_pop=sum(suscept_pop)),by=.(run_num, year)]
orig.inc[,inc:=new_hiv/suscept_pop*100]
orig.inc[,variable:=paste0('draw',run_num)]
new.inc <- melt(out.data, id.vars = c('year'))
long.ratios <- merge(orig.inc, new.inc, by=c('year', 'variable'))[,.(year, run_num, inc, value)]
long.ratios[,ratio:=value/inc]
long.ratios[inc==0, ratio:=1]

wide.ratios <- data.table(dcast(long.ratios[,.(year, run_num, ratio)], year ~ run_num, value.var='ratio'))
setnames(wide.ratios, as.character(1:n.draws), paste0('ratio',1:n.draws))
wide.ratios <- wide.ratios[order(year),]

write.csv(wide.ratios, paste0('/strPath/',loc,'_inc_ratios.csv'), row.names=F)

