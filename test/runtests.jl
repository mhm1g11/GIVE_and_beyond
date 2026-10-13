using Test
include(joinpath(@__DIR__,"..","scripts","ScenarioConfig.jl"))
using .ScenarioConfig
@testset "Portable scenario and alignment safeguards" begin
    c=load_config(joinpath(@__DIR__,"..","examples","run.toml"))
    @test validate_inputs(c)
    @test length(c.scenarios)==1
    @test isabspath(c.scenarios[1].path)
    @test_throws ErrorException validate_inputs(c;external=true)
    mktempdir() do dir
        scenario=joinpath(dir,"policy.csv")
        cp(c.scenarios[1].path,scenario)
        changed=merge(c,(;scenarios=[(name="new_policy",path=scenario)]))
        @test validate_inputs(changed)
        original=replace(read(scenario,String), "\r\n"=>"\n")
        write(scenario,replace(original,"2030,0.01"=>"2030,-0.01"))
        @test_throws ErrorException validate_inputs(changed)
        write(scenario,replace(original,"2030,0.01"=>"2030,NaN"))
        @test_throws ErrorException validate_inputs(changed)
        write(scenario,replace(original,"2030,0.01\n"=>""))
        @test_throws ErrorException validate_inputs(changed)
        write(scenario,original*"2030,0.01\n")
        @test_throws ErrorException validate_inputs(changed)
        write(scenario,original)
        labor=joinpath(dir,"labor.csv")
        write(labor,replace(read(c.labor_design,String),"1,730,"=>"1,731,"))
        @test_throws ErrorException validate_inputs(merge(changed,(;labor_design=labor)))
        write(labor,replace(read(c.labor_design,String),"1362,2,"=>"1362,1,"))
        @test_throws ErrorException validate_inputs(merge(changed,(;labor_design=labor)))
        @test_throws ErrorException validate_inputs(merge(c,(;trials=3)))
    end
end

using TOML, SHA
@testset "Cross-stage provenance prevents changed-input combination" begin
    mktempdir() do dir
        input=joinpath(dir,"input.csv");write(input,"year,avoided_ch4_mt\n2025,0\n")
        hash=bytes2hex(open(sha256,input))
        c=(output_dir=dir,)
        @test_throws ErrorException verify_stage_provenance(c,"production")
        for stage in ("climate","ozone")
            out=joinpath(dir,"provenance",stage*"_production");mkpath(out)
            open(joinpath(out,"input_code_hashes.toml"),"w") do io
                TOML.print(io,Dict("sha256"=>Dict(input=>hash)))
            end
        end
        @test verify_stage_provenance(c,"production")
        write(input,"changed")
        @test_throws ErrorException verify_stage_provenance(c,"production")
    end
end

include(joinpath(@__DIR__,"..","scripts","check_syntax.jl"))
