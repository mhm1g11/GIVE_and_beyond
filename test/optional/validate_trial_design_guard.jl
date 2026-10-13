using Test, FileIO, CSVFiles, DataFrames
include(joinpath(@__DIR__, "..", "..", "analysis", "src", "AlignedTrialDesign.jl"))
using .AlignedTrialDesign

@testset "Protect production trial design" begin
    production = joinpath(@__DIR__, "..", "..", "examples", "mc_trial_design.csv")
    original = read(production)
    production_n = nrow(DataFrame(load(production)))
    # Exercise replacement ONLY on a temporary copy, never the real design.
    mktempdir() do temp
        path = joinpath(temp, "design.csv")
        write(path, original)
        design = load_or_create_trial_design(path; n_trials=production_n)
        @test nrow(design) == production_n
        @test read(path) == original
        @test_throws ErrorException load_or_create_trial_design(path; n_trials=5)
        @test read(path) == original
        @test nrow(load_or_create_trial_design(path; n_trials=5, allow_replace=true)) == 5
        fresh = joinpath(temp, "new.csv")
        generated = load_or_create_trial_design(fresh)
        @test nrow(generated) == 100
        # Separate RNGs remain deterministic; a different seed does not replace an existing design.
        bytes = read(fresh)
        @test load_or_create_trial_design(fresh; seed=123).rffsp_id == generated.rffsp_id
        @test read(fresh) == bytes
        extended = load_or_create_trial_design(fresh; n_trials=1000, allow_extend=true)
        @test extended.trialnum == collect(1:1000)
        @test isequal(extended[1:100, :], generated)
        @test_throws ErrorException load_or_create_trial_design(fresh; n_trials=100, allow_extend=true)
        # Historical identities need not match the current seeded generator.
        generated.rffsp_id[1] = mod1(generated.rffsp_id[1] + 1, 10000)
        save(fresh, generated)
        extended = load_or_create_trial_design(fresh; n_trials=1000, allow_extend=true)
        @test isequal(extended[1:100, :], generated)
        @test nrow(extended) == 1000
    end
    @test read(production) == original
end
