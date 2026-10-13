include("ScenarioConfig.jl")
using .ScenarioConfig
c=config_from_args()
i=findfirst(==("--stage"),ARGS)
i!==nothing && i<length(ARGS) || error("Use --stage climate|ozone|combine|reference")
stage=ARGS[i+1]
files=Dict("climate"=>"15_run_policy_scenarios.jl","ozone"=>"16_run_policy_ozone.jl","combine"=>"17_combine_policy_results.jl","reference"=>"05_build_momm_reference_socioeconomics.jl")
haskey(files,stage) || error("Unknown stage $stage")
mode="--production" in ARGS ? "production" : "--data-smoke" in ARGS ? "data_smoke" : nothing
stage=="reference" || mode!==nothing || error("Use exactly one of --data-smoke or --production")
!("--production" in ARGS && "--data-smoke" in ARGS) || error("Select one mode")
validate_inputs(c;external=stage in ("climate","ozone"),ozone=stage=="ozone")
if stage=="reference"
    ispath(c.momm_socio) && error("Reference already exists; choose a new path")
else
    root=Dict("climate"=>"policy_scenarios","ozone"=>"policy_ozone","combine"=>"policy_combined")[stage]
    ispath(joinpath(c.output_dir,root,mode)) && error("Output exists; choose a new output_dir")
end
ENV["MIMIGIVE_LABOR_DATA"]=c.labor_root
ENV["DATADEPS_ALWAYS_ACCEPT"]="false"
println("Stage $stage: model/CIAM stages can be expensive; see docs/VALIDATION.md.")
stage=="combine" && verify_stage_provenance(c,mode)
record_provenance(c,stage,something(mode,"reference"))
# Separate module avoids shared constants between stages and the configuration loader.
module PolicyStage end
Base.include(PolicyStage,joinpath(@__DIR__,"..","analysis","scripts",files[stage]))

stage == "reference" || PolicyStage.main()
