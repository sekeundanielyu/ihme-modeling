#Format Lai tables to use for Asthma

df = read.csv("J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/table_s3_from_Lai_et_al_2009_someformatting.csv", stringsAsFactors = F)

names(df) = c('centre','year_id','N', 'cur_whez_n','cur_whez_per','asthma_ever_N', 'asthma_ever_per')

#loop through rows and try to assign parent locations
df$parent_location = ""
for(i in 2:nrow(df)){
  #print(i)
  
  #if the row is a valid data point, iterate up the list until you find a row where it is NA
  if(!is.na(df$year_id[i])){
    val = 0
    iter = i
    while(val == 0){
     #print(paste(val,iter))
     iter = iter - 1
     val = ifelse(is.na(df$year_id[iter]), 1,0)
    }
    
    df$parent_location[i] = df$centre[iter]
  }
  
}

#Remove Totals and assign location names
df=df[!grepl('English',df$centre),]
df=df[df$centre!="Region Total" & df$centre!= "Country Total" & df$centre!="Global Total" & df$centre!="",]

#remove if no year id (indicitive of only one country location)
df = df[!is.na(df$year_id),]

#sanitize names
df$centre[grep('[*]', df$centre)] = substr(df$centre[grep('[*]', df$centre)],1,nchar(df$centre[grep('[*]', df$centre)])-1) #remove astrisks

#remove paranthesis in a janky way
for(i in 1:nrow(df)){
  if(grepl('\\(',df$centre[i])){
    print(df$centre[i])
    df$centre[i] = substr(df$centre[i],1,regexpr('\\(',df$centre[i])[1]-2)
    print(df$centre[i])
  }
}


#Identify centres that are in subnational locations
df$subnat = 0
df$subnat[df$parent_location %in% c('Brazil', 'India', 'Mexico', 'South Africa','Sweden')] =1
df$count = 1
df_agg = aggregate(cbind(df$N, df$cur_whez_n,df$year_id, df$count, df$subnat)~df$parent_location, FUN = sum)
names(df_agg) = c('location_name','Sample Size','Cases','year_id','numcentres','subnat')


#fix names
df_agg$location_name[df_agg$location_name=='Syrian Arab Republic'] = "Syria"
df_agg$location_name[df_agg$location_name== 'Hong Kong'] = 'Hong Kong Special Administrative Region of China'
df_agg$location_name[df_agg$location_name== 'Sultanate of Oman'] = 'Oman'
df_agg$location_name[df_agg$location_name== 'Serbia and Montenegro'] = 'Serbia'

#merge in names
locs= read.csv('J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/loc_ids.csv')
df_m = merge(df_agg, locs, by='location_name') #this drops Isle of Man, Niue
df_m = df_m[df_m$location_id!=533, ] #georgia might accidently assigned twice
#add subnational points
sublocs = read.csv('J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/lai_sites_to_loc_id.csv', stringsAsFactors = F)
df_sub = merge(df,sublocs,by='centre', all=F)
df_sub_agg = aggregate(cbind(df_sub$N, df_sub$cur_whez_n,df_sub$year_id, df_sub$count, df_sub$subnat)~df_sub$location_id, FUN = sum)
names(df_sub_agg) = c('location_id','Sample Size','Cases','year_id','numcentres','subnat')

#Aggregate to the subnational locations and append to the national results
data_s3 = rbind(df_m[,c('Sample Size','Cases','year_id','location_id','numcentres')],df_sub_agg[,c('Sample Size','Cases','year_id','location_id','numcentres')])
data_s3$age_start = 6
data_s3$age_end = 7

write.csv(data_s3, file = paste0('J:/WORK/04_epi/01_database/02_data/resp_asthma/1907/01_input_data/00_lit/00_pdfs/00_extracted/lai_tbl_s3_extracted.csv'))






