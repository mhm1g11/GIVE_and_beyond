
using Test, TOML, SHA
include(joinpath(@__DIR__,"..","scripts","ScenarioConfig.jl"))
using .ScenarioConfig
@testset "Run provenance records science without model execution" begin
    original=load_config(joinpath(@__DIR__,"..","examples","run.toml"))
    mktempdir() do dir
        c=merge(original,(;output_dir=dir))
        out=record_provenance(c,"fixture","production")
        record=TOML.parsefile(joinpath(out,"input_code_hashes.toml"))
        @test record["julia_version"]==string(VERSION)
        @test record["sha256"][c.path]==bytes2hex(open(sha256,c.path))
        @test record["sha256"][c.scenarios[1].path]==bytes2hex(open(sha256,c.scenarios[1].path))
        @test haskey(record["sha256"],normpath(joinpath(@__DIR__,"..","data","Dimension_countries.csv")))
        @test isfile(joinpath(out,"mc_trial_design.csv"))
        @test isfile(joinpath(out,"labor_trial_design.csv"))
        @test_throws ErrorException record_provenance(c,"fixture","production")
    end
end
