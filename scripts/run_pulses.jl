include(joinpath(@__DIR__,"..","analysis","scripts","config.jl"))
validate_inputs(RELEASE_CONFIG;external=true,ozone=false)
using MimiGIVE, DataFrames, FileIO, CSVFiles
include(joinpath(@__DIR__,"..","analysis","src","ResearchClimateProduction.jl"))
idx=findfirst(==("--years"),ARGS)
idx!==nothing && idx<length(ARGS) || error("Use --years 2025,2030,...")
years=parse.(Int,split(ARGS[idx+1],','))
!isempty(years) && length(unique(years))==length(years) && all(2020 .<= years .<= 2300) || error("Invalid pulse years")
out=joinpath(RELEASE_CONFIG.output_dir,"pulse_factors")
ispath(out) && error("Pulse output exists; choose a new output_dir")
ENV["DATADEPS_ALWAYS_ACCEPT"]="false"
record_provenance(RELEASE_CONFIG,"pulses","production")
design=MimiGIVE.load_labor_trial_design(RELEASE_CONFIG.labor_design,RELEASE_CONFIG.trial_design)
ResearchClimateProduction.build_labor_library(;design,seed=RELEASE_CONFIG.seed,output_dir=out,pulse_years=years,
    responses=LABOR_RESPONSES,last_year=FULL_MODEL_HORIZON,discount_rates=DISCOUNT_RATES,gas=GAS,pulse_size=PULSE_SIZE_MT)
