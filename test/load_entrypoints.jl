
using Test
root=normpath(joinpath(@__DIR__,".."))
empty!(ARGS); append!(ARGS,["--config",joinpath(root,"examples","run.toml"),"--data-smoke"])
ENV["DATADEPS_ALWAYS_ACCEPT"]="false"
module ClimateDefinitions end
module OzoneDefinitions end
module CombineDefinitions end
@testset "Definition-only entry-point checks; no model execution" begin
    for (mod,name) in [(ClimateDefinitions,"15_run_policy_scenarios.jl"),(OzoneDefinitions,"16_run_policy_ozone.jl"),(CombineDefinitions,"17_combine_policy_results.jl")]
        Base.include(mod,joinpath(root,"analysis","scripts",name))
        @test mod.parse_mode()==:data_smoke
        @test mod.RELEASE_CONFIG.trials==2
    end
    @test abspath(pathof(ClimateDefinitions.MimiGIVE))==joinpath(root,"src","MimiGIVE.jl")
    @test Set(keys(ClimateDefinitions.load_scenarios(:data_smoke)))==Set(["synthetic_policy"])
    @test Set(keys(OzoneDefinitions.load_scenarios(:data_smoke)))==Set(["synthetic_policy"])
    @test ClimateDefinitions.scenario_addition(ClimateDefinitions.load_scenarios(:data_smoke)["synthetic_policy"],collect(1750:2300))[2030-1750+1] == -0.01
    @test CombineDefinitions.assert_expected_scenarios(CombineDefinitions.DataFrame(scenario=["synthetic_policy"]),"fixture")===nothing
end
