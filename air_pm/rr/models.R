#----HEADER-------------------------------------------------------------------------------------------------------------
# Project: RF: air_pm
# Purpose: Return model code for various models in STAN
#***********************************************************************************************************************

returnModel <- function(model, source.num) {
  
  model.dir <- file.path(root, "_code/risks/air_pm/rr/_lib")

  if (model == "power2") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(alpha = 50, beta = 0.1, gamma = 0.25)
    }
    
    parameters <- c('alpha', 'beta', 'gamma')
    
  }
  
  if (model == "power2_simsd") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(alpha = 50, beta = 0.1, gamma = 0.25, delta = 5)
    }
    
    parameters <- c('alpha', 'beta', 'gamma', 'delta')
    
  }
  
  if (model == "power2_simsd_source") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(alpha = 50, beta = 0.1, gamma = 0.25, delta = rep(5, source.num))
    }
    
    parameters <- c('alpha', 'beta', 'gamma', 'delta')
    
  }
  
  if (model == "simplified") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(beta = .5, rho = 0.25)
    }
    
    parameters <- c('beta', 'rho')
    
  }
  
  if (model == "simrel") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(beta = .5, rho = 0.25, tmrel = 0.25)
    }
    
    parameters <- c('beta', 'rho', 'tmrel')
    
  }
  
  if (model == "simsd") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(beta = .5, rho = 0.25, tmrel = 0.25, delta = 5)
    }
    
    parameters <- c('beta', 'rho', 'tmrel', 'delta')
    
  }
  
  if (model == "loglin") {
    
    # read in model file
    model.file <- file.path(model.dir, paste0("model_", model, ".stan"))
    
    # prime the initialization function with some numbers you think are reasonable to start
    # the step shouldnt matter that much as long as the model starts to converge
    init.f <- function() {
      list(beta = .5, gamma = 0.25)
    }
    
    parameters <- c('beta', 'gamma')
    
  }
    
  model.info <- list("model"=model.file, "initialize"=init.f, 'parameters'=parameters)
  
  return(model.info)
  
}