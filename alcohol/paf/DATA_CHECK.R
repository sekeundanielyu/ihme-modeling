test=function(){
  cat("
        ***********************************************************************
        For this program to run properly, the variable BINGERS is defined 
        as the proportion of bingers among drinkers and the variables BINGE_A 
        and BINGERS need to be consistent across all regions. Based on new
        evidence, this threshold should be 60g/day for both men and women and 
        represents the limit after which all drinkers are automatically bingers.
        ***********************************************************************
      ")
ret=readline("Is the input file set up properly? [y/n]")
return(ret)
}

test_data=test()