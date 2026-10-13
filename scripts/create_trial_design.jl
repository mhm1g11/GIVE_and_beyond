include("ScenarioConfig.jl")
using .ScenarioConfig, Random
include(joinpath(@__DIR__,"..","analysis","src","AlignedTrialDesign.jl"))
using .AlignedTrialDesign
c=config_from_args()
!ispath(c.trial_design) && !ispath(c.labor_design) || error("Refusing to replace existing designs; configure new file paths")
_,rows=read_numeric_csv(joinpath(@__DIR__,"..","examples","labour_model_names.csv"))
labels=only.(rows)
mkpath(dirname(c.trial_design));mkpath(dirname(c.labor_design))
design=load_or_create_trial_design(c.trial_design;n_trials=c.trials,seed=c.seed)
ids=rand(MersenneTwister(c.seed+2),2:16,c.trials)
open(c.labor_design,"w") do io
    println(io,"trialnum,rffsp_id,fair_parameter_set_id,labor_model_id,labor_model")
    for (i,row) in enumerate(eachrow(design))
        println(io,join([row.trialnum,row.rffsp_id,row.fair_parameter_set_id,ids[i],labels[ids[i]]],','))
    end
end
println("Created new aligned design. Labour RNG: Julia MersenneTwister(seed+2), not the historical Python generator.")
