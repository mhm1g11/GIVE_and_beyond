using MimiGIVE, Mimi, Test, CSVFiles, DataFrames
module PublishedLabor
using Mimi, MimiGIVE
reference = joinpath(MimiGIVE.labor_data_dir(),"reference/src/utils.jl")
include_string(@__MODULE__, replace(read(reference,String), "joinpath(@__DIR__, \"..\", \"data\", " => "joinpath(MimiGIVE.labor_data_dir(), "), reference)
include(joinpath(MimiGIVE.labor_data_dir(),"reference/src/components/labor.jl"))
include(joinpath(MimiGIVE.labor_data_dir(),"reference/src/components/AgricultureShare.jl"))
end
countries = String.(DataFrame(load(joinpath(MimiGIVE.labor_data_dir(), "region_crosswalk.csv"))).iso3)
function isolated(labor, share, inputs, modelid)
    m = Model(); set_dimension!(m, :time, 2020:2030)
    set_dimension!(m, :country, countries); set_dimension!(m, :gcm, inputs.gcms)
    add_comp!(m, share, :Share); add_comp!(m, labor, :Labor)
    # Controlled climate-only fixture: knots, between-knots, and extrapolation.
    T = [-0.1, 0., 0.5, 1., 1.25, 2., 2.75, 3., 3.5, 4., 5.] .+ 0.82
    pop = fill(1.,11,184)
    gdp = repeat(reshape(inputs.ypc2017 ./ 1000,1,:),11,1) .* collect(range(1.,1.5,length=11))
    for (p,v) in [(:ypc2017, inputs.ypc2017), (:agrish0,inputs.agrish0), (:gdp,gdp), (:population,pop)]
        update_param!(m,:Share,p,v)
    end
    for (p,v) in [(:gdp,gdp),(:population,pop),(:temp,T),(:gcm,modelid),(:gtap_ag_impacts,inputs.ag),(:gtap_nonag_impacts,inputs.nonag)]
        update_param!(m,:Labor,p,v)
    end
    connect_param!(m,:Labor=>:agrish,:Share=>:agrish)
    run(m); m
end
@testset "Published labour equivalence" begin
    for response in (:ISO,:Lancet)
        inp = MimiGIVE.labor_inputs(countries,response)
        # Independent published loader validates ratios and country/model mapping.
        raw = PublishedLabor.get_labor_gtap_df(joinpath(MimiGIVE.labor_data_dir(),"gtap_output","20260428_Plants_People_results_v4_$(response)_Revision.csv"))
        mapping = DataFrame(load(joinpath(MimiGIVE.labor_data_dir(),"region_crosswalk.csv")))
        lookup = Dict((r.gtap,r.temp,r.gcm)=>(r.ag_impact_fraction,r.nonag_impact_fraction) for r in eachrow(raw))
        for (i,c) in enumerate(countries), (j,t) in enumerate(1.:0.5:4.), (k,g) in enumerate(inp.gcms)
            pair=lookup[(mapping.gtap[i],t,g)]
            @test inp.ag[i,j,k] == pair[1]
            @test inp.nonag[i,j,k] == pair[2]
        end
        for g in 1:16
            a=isolated(PublishedLabor.Labor,PublishedLabor.AgricultureShare,inp,g)
            b=isolated(MimiGIVE.Labor,MimiGIVE.LaborSectorShare,inp,g)
            for v in (:laborcost,:laborcost_ag,:laborcost_nonag,:temp_normalized)
                @test isequal(a[:Labor,v],b[:Labor,v])
            end
            @test isequal(a[:Share,:agrish],b[:Share,:agrish])
            @test all(x -> 0 < x < 1, b[:Share,:agrish])
        end
        println("EXACT published equivalence: ",response,"; all 16 models, 184 countries, knots/interpolation/extrapolation")
    end
end
