include("ScenarioConfig.jl")
using .ScenarioConfig
c=config_from_args()
validate_inputs(c;external="--external" in ARGS)
println("PASS: scenario schema, complete annual horizon, aligned $(c.trials)-trial identities" )
println("Validation only; no model execution or dependency installation.")
