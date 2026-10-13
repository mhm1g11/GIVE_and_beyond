
using Test, Mimi, Interpolations
module IsolatedLabor
using Mimi, Interpolations
include(joinpath(@__DIR__,"..","src","utils","labor.jl"))
include(joinpath(@__DIR__,"..","src","components","LaborSectorShare.jl"))
include(joinpath(@__DIR__,"..","src","components","labor_damages.jl"))
end
@testset "Synthetic labour component, no GIVE/CIAM or external data" begin
    m=Model();set_dimension!(m,:time,2020:2022);set_dimension!(m,:country,["AAA","BBB"]);set_dimension!(m,:gcm,["synthetic"])
    add_comp!(m,IsolatedLabor.LaborSectorShare,:Share);add_comp!(m,IsolatedLabor.Labor,:Labor)
    # Baseline per-capita income doubles in the middle year, exercising share elasticity.
    gdp=[10.0 20.0;20.0 40.0;10.0 20.0];pop=ones(3,2);shares=[0.2,0.4]
    for (p,v) in [(:ypc2017,[10000.,20000.]),(:agrish0,shares),(:gdp,gdp),(:population,pop)]
        update_param!(m,:Share,p,v)
    end
    ag=reshape(repeat(-0.02 .* collect(1.:0.5:4.),inner=2),2,7,1)
    nonag=reshape(repeat(-0.01 .* collect(1.:0.5:4.),inner=2),2,7,1)
    for (p,v) in [(:gdp,gdp),(:population,pop),(:temp,[0.82,2.07,5.82]),(:gcm,1),(:gtap_ag_impacts,ag),(:gtap_nonag_impacts,nonag)]
        update_param!(m,:Labor,p,v)
    end
    connect_param!(m,:Labor=>:agrish,:Share=>:agrish)
    run(m)
    @test m[:Labor,:temp_normalized] ≈ [0.,1.25,5.]
    @test m[:Labor,:laborcost][1,:] ≈ zeros(2)
    @test m[:Share,:agrish][2,:] ≈ shares .* 2.0^(-0.31)
    @test m[:Labor,:laborcost][2,:] ≈ gdp[2,:] .* (1.25 .* (0.01 .+ 0.01 .* shares .* 2.0^(-0.31)))
    @test m[:Labor,:laborcost][3,:] ≈ gdp[3,:] .* (5. .* (0.01 .+ 0.01 .* shares))
    @test m[:Labor,:laborcost] ≈ m[:Labor,:laborcost_ag] .+ m[:Labor,:laborcost_nonag]
end
include(joinpath(@__DIR__,"..","analysis","src","MethaneOzoneMortality.jl"))
using .MethaneOzoneMortality, DataFrames
@testset "Synthetic ozone response scaling" begin
    years=[2020,2021,2022]
    reference_delta=reference_methane_delta_ppb.(years)
    @test reference_delta[1] == 100.0
    @test reference_delta[2]/reference_delta[1] ≈ exp(-1/11.8)
    @test give_methane_scaling(years,reference_delta) ≈ ones(3)
    @test give_methane_scaling(years,-reference_delta) ≈ -ones(3)
end
