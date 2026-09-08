using FileIO
using CSVFiles
using DataFrames

include(
    joinpath(
        @__DIR__,
        "..",
        "src",
        "MethaneOzoneMortality.jl"
    )
)

using .MethaneOzoneMortality

const MOMM_ROOT = normpath(
    joinpath(
        @__DIR__,
        "..",
        "external",
        "MOMM-RFT"
    )
)

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

if global_diff < 1e-6 &&
   per_mt_diff < 1e-9

    println()
    println(
        "PASS: Julia reproduces the original MOMM-RFT 2020 reference mortality."
    )

else

    println()
    println(
        "FAIL: Julia does not reproduce the MOMM-RFT reference result."
    )

end