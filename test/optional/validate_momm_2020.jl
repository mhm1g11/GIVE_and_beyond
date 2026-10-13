using Test
using FileIO
using CSVFiles
using DataFrames

include(joinpath(@__DIR__,"..","..","analysis","src","MethaneOzoneMortality.jl"))
using .MethaneOzoneMortality
const MOMM_ROOT = get(ENV,"MIMIGIVE_MOMM_DATA",joinpath(@__DIR__,"..","..","external","MOMM-RFT"))
const EXPECTED_GLOBAL_DEATHS =
    210324.797541092

const EXPECTED_DEATHS_PER_MT =
    764.817445603972

println("MOMM-RFT JULIA REFERENCE VALIDATION")
println("===================================")
println()

reference =
    load_momm_reference(MOMM_ROOT)

years = collect(2020:2100)

# ================================================================
# Original MOMM-RFT reference experiment
#
# Pulse:
#   275 Mt CH4
# Year:
#   2020
#
# Because this is identical to the BenMAP reference pulse,
# the methane scaling should equal exactly 1 in every year.
# ================================================================

scales = legacy_methane_scaling(
    years;
    pulse_year = 2020,
    pulse_size_mt = 275.0
)

println(
    "Methane scale min: ",
    minimum(scales)
)

println(
    "Methane scale max: ",
    maximum(scales)
)

results =
    calculate_ozone_deaths(
        reference,
        years,
        scales
    )

global_annual =
    aggregate_geography(
        results,
        "globe"
    )

eu27_annual =
    aggregate_geography(
        results,
        "EU27"
    )

germany_annual =
    aggregate_geography(
        results,
        "DEU"
    )

global_total =
    sum(
        global_annual.ozone_respiratory_deaths
    )

eu27_total =
    sum(
        eu27_annual.ozone_respiratory_deaths
    )

germany_total =
    sum(
        germany_annual.ozone_respiratory_deaths
    )

deaths_per_mt =
    global_total / 275.0

println()
println("REFERENCE RESULTS")
println("=================")

println(
    "Global respiratory deaths: ",
    global_total
)

println(
    "Respiratory deaths / Mt CH4: ",
    deaths_per_mt
)

println(
    "EU27 respiratory deaths: ",
    eu27_total
)

println(
    "Germany respiratory deaths: ",
    germany_total
)

println()
println("VALIDATION")
println("==========")

global_diff =
    abs(
        global_total -
        EXPECTED_GLOBAL_DEATHS
    )

per_mt_diff =
    abs(
        deaths_per_mt -
        EXPECTED_DEATHS_PER_MT
    )

println(
    "Global difference: ",
    global_diff
)

println(
    "Per-Mt difference: ",
    per_mt_diff
)

@testset "McDuffie original physical benchmark" begin
    @test global_diff < 1e-6
    @test per_mt_diff < 1e-9
    @test all(scales .== 1.0)
end

@testset "Stored atmospheric and epidemiological responses" begin
    expected = Dict("CESM2"=>250812.287, "GFDL"=>173113.179,
                    "GISS"=>166748.550, "HadGEM"=>323143.534,
                    "MIROC"=>137893.729, "MMM"=>210324.798)
    for (model, total) in expected
        central = load_momm_reference(MOMM_ROOT; atmospheric_model=model)
        lower = load_momm_reference(MOMM_ROOT; atmospheric_model=model, health_response="lower")
        upper = load_momm_reference(MOMM_ROOT; atmospheric_model=model, health_response="upper")
        @test isapprox(sum(central.reference_deaths), total; atol=0.00051, rtol=0)
        @test all(lower.reference_deaths .< central.reference_deaths)
        @test all(central.reference_deaths .< upper.reference_deaths)
        @test central.LocID == lower.LocID == upper.LocID
        @test central.year == lower.year == upper.year
    end
    explicit = load_momm_reference(MOMM_ROOT; atmospheric_model="MMM", health_response="central")
    @test reference.reference_deaths == explicit.reference_deaths
    raw = DataFrame(load(joinpath(MOMM_ROOT, "input", "BenMAP",
                     "Country Results Interpolated 2020-2100 by Model.csv")))
    raw = sort!(filter(r -> r.Model == "MMM", raw), [:column, :ModelYear])
    @test reference.reference_deaths == raw[!, Symbol("Inverse.PE")]
    @test_throws ArgumentError load_momm_reference(MOMM_ROOT; atmospheric_model="invalid")
    @test_throws ArgumentError load_momm_reference(MOMM_ROOT; health_response="sampled_beta")
    # Same pulse normalisation and linear scaling as the original implementation.
    unit = legacy_methane_scaling(years; pulse_year=2020, pulse_size_mt=1.0)
    @test isapprox(sum(calculate_ozone_deaths(reference, years, unit).ozone_respiratory_deaths),
                   EXPECTED_DEATHS_PER_MT; atol=1e-9, rtol=0)
end
