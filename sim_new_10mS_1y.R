### Single Drug - low Weibull
setwd("./right-simulation")
pkg = list("simmer",
           "data.table",
           "plyr",
           "dplyr",
           "tidyr",
           "reshape2",
           "ggplot2",
           "downloader",
           "msm",
           "quantmod")
invisible(lapply(pkg, require, character.only = TRUE))
rm(list=ls())

env  <- simmer("RIGHT-v1.1")

exec.simulation <- function(inputs)
{
        set.seed(123)
        env  <<- simmer("RIGHT-v1.1")
        traj <- simulation(env, inputs)
        env %>% create_counters(counters)
        
        env %>%
                add_generator("patient", traj, at(rep(0, inputs$vN)), mon=2) %>%
                run(365*inputs$vHorizon+1) %>% # Simulate just past horizon
                wrap()
        
        get_mon_arrivals(env, per_resource = T)
}

source("./init_jon_sept18.R")
options(digits=5)
inputs$vN <- 1000
inputs$vHorizon <- 1
#inputs$warfarin$vscale_timetowarfarin <- epsilon
#inputs$clopidogrel$vDAPTScale <- epsilon
inputs$simvastatin$vScale <- epsilon
#inputs$clopidogrel$vRRRepeat.DAPT <- 0 #only for low-weibull runs, to fix retrigger clopidogrel prescription

###uploaded myopathy risks
inputs$simvastatin$vMildMyoSimNoVar=0.05*4  # Simvastatin Mild Myopathy Baseline Risk
inputs$simvastatin$vMildMyoAltNoVar=0.05*4  # Alternate Drug Mild Myopathy Baseline Risk
inputs$simvastatin$vModMyoSimNoVar=0.00011*4  # Simvastatin Mild Myopathy Baseline Risk
inputs$simvastatin$vModMyoAltNoVar=0.00011*4  # Alternate Drug Mild Myopathy Baseline Risk
inputs$simvastatin$vSevMyoSimNoVar=0.000034*4 # Simvastatin Mild Myopathy Baseline Risk
inputs$simvastatin$vSevMyoAltNoVar=0.000034*4 # Alternate Drug Mild Myopathy Baseline Risk

###Single Drug 
inputs$vDrugs = list(vSimvastatin = T, 
                     vWarfarin = F,
                     vClopidogrel = F)

results <- NULL
attributes <- NULL
for(preemptive in "None")
{
        for(reactive in c("None","Single"))
        {
                if(preemptive == "PREDICT" && reactive == "Panel") {next}
                if(preemptive == "PREDICT" && reactive == "Single") {next}
                if(preemptive == "Panel" && reactive == "Single") {next}
                if(preemptive == "Panel" && reactive == "Panel") {next}
                #cat("Running ", preemptive, "/", reactive, "\n")
                
                if(reactive=="None") {strat <- "None"}
                if(reactive=="Single") {strat <- "Reactive Single"}
                
                inputs$vPreemptive <- preemptive
                inputs$vReactive   <- reactive
                run <- exec.simulation(inputs)
                # run$preemptive <- preemptive
                # run$reactive   <- reactive
                run$strategy <- strat
                
                at <- arrange(get_mon_attributes(env),name,key,time) %>% filter(key %in% c("aAgeInitial","aGender"))
                # at$preemptive <- preemptive
                # at$reactive   <- reactive
                at$strategy <- strat
                
                if(is.null(results)) { results <- run } else  {results <- rbind(results, run)}
                if(is.null(attributes)) { attributes <- at } else  {attributes <- rbind(attributes, at)}
                rm(run)
                rm(at)
        }
}

###events summary
DT <- data.table(results)
print("Summary")
summ <- DT[, .N, by = list(resource, strategy)]
save(results,file=paste0("/gpfs23/data/h_imph/gravesj/right/jonathan/raw_sim_newS_",num_seed,"_1y.rda")) #raw traj
# save(summ,file=paste0("/gpfs23/data/h_imph/gravesj/right/jonathan/summ_sim_newS_",num_seed,"_1y.rda"))
attributes <- attributes %>% dcast(name+strategy~key,value.var="value") 
save(attributes,file=paste0("/gpfs23/data/h_imph/gravesj/right/jonathan/at_sim_newS_",num_seed,"_1y.rda"))

ae <- c("revasc_pci","revasc_cabg","bleed_ext_maj_nonfatal","bleed_int_maj_nonfatal","bleed_min_nonfatal","bleed_fatal",
        "st_fatal","st_pci","st_cabg","mi_cabg","mi_pci","mi_med_manage","mild_myopathy","mod_myopathy","sev_myopathy","rahbdo_death",
        "cvd","cvd_death","in_range","MajorBleed_ICH","MajorBleed_ICH_Fatal","MajorBleed_GI","MajorBleed_GI_Fatal","MajorBleed_Other",
        "MajorBleed_Other_Fatal","MinorBleed","Stroke_MinorDeficit","Stroke_MajorDeficit","Stroke_Fatal","DVTPE_Fatal","DVT","PE", "cabg_bleed","dapt_stroke")

ct <- results %>% filter(resource %in% ae) %>% group_by(name,strategy,resource) %>% summarise(n=n()) %>%
        ungroup() %>% dcast(name+strategy~resource,value.var="n") #event count

###Costs
source("./costs_ICER_36525.R")
inputs$vN <- 1000
s1 <- cost.qaly(subset(results,strategy=="None"),inputs) %>% mutate(strategy="None")
s2 <- cost.qaly(subset(results,strategy=="Reactive Single"),inputs) %>% mutate(strategy="Reactive Single")

out <- rbind(s1,s2) %>% inner_join(attributes,by = c("name","strategy")) %>% left_join(ct,by = c("name","strategy"))
save(out,file=paste0("/gpfs23/data/h_imph/gravesj/right/jonathan/cost_sim_newS_",num_seed,"_1y.rda"))


