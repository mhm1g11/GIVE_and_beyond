using Mimi
using MimiGIVE
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

const PULSE_YEAR = 2020
const PULSE_SIZE_MT = 1.0
const LAST_YEAR = 2100

println("GIVE-FIRST OZONE MORTALITY ATMOSPHERE SWAP")
println("==========================================")
println()

# ================================================================
# Load validated McDuffie health-response reference
# ================================================================

reference =
    load_momm_reference(MOMM_ROOT)

years =
    collect(PULSE_YEAR:LAST_YEAR)

# ================================================================
# A. Original MOMM-RFT atmospheric methane representation
# ================================================================

legacy_scales =
    legacy_methane_scaling(
        years;
        pulse_year = PULSE_YEAR,
        pulse_size_mt = PULSE_SIZE_MT
    )

legacy_results =
    calculate_ozone_deaths(
        reference,
        years,
        legacy_scales
    )

legacy_global =
    aggregate_geography(
        legacy_results,
        "globe"
    )

legacy_eu27 =
    aggregate_geography(
        legacy_results,
        "EU27"
    )

legacy_deu =
    aggregate_geography(
        legacy_results,
        "DEU"
    )

legacy_global_total =
    sum(legacy_global.ozone_respiratory_deaths)

legacy_eu27_total =
    sum(legacy_eu27.ozone_respiratory_deaths)

legacy_deu_total =
    sum(legacy_deu.ozone_respiratory_deaths)

# ================================================================
# B. GIVE/FaIR atmospheric methane representation
# ================================================================

m =
    MimiGIVE.get_model()

mm =
    MimiGIVE.get_marginal_model(
        m;
        year = PULSE_YEAR,
        gas = :CH4,
        pulse_size = PULSE_SIZE_MT
    )

run(mm)

give_years =
    collect(dim_keys(mm.base, :time))

ch4_base =
    mm.base[:ch4_cycle, :CH₄]

ch4_modified =
    mm.modified[:ch4_cycle, :CH₄]

delta_ch4 =
    ch4_modified .- ch4_base

# Restrict to the period represented by the McDuffie health data.
give_indices = [
    findfirst(==(year), give_years)
    for year in years
]

any(isnothing, give_indices) &&
    error("A requested year is missing from the GIVE model.")

give_delta_2020_2100 = [
    Float64(delta_ch4[idx])
    for idx in give_indices
]

give_scales =
    give_methane_scaling(
        years,
        give_delta_2020_2100
    )

give_results =
    calculate_ozone_deaths(
        reference,
        years,
        give_scales
    )

give_global =
    aggregate_geography(
        give_results,
        "globe"
    )

give_eu27 =
    aggregate_geography(
        give_results,
        "EU27"
    )

give_deu =
    aggregate_geography(
        give_results,
        "DEU"
    )

give_global_total =
    sum(give_global.ozone_respiratory_deaths)

give_eu27_total =
    sum(give_eu27.ozone_respiratory_deaths)

give_deu_total =
    sum(give_deu.ozone_respiratory_deaths)

# ================================================================
# Results
# ================================================================

println("1 MT CH4 PULSE IN 2020")
println("======================")
println()

println("Original MOMM-RFT methane representation:")
println("  Globe   : ", legacy_global_total)
println("  EU27    : ", legacy_eu27_total)
println("  Germany : ", legacy_deu_total)

println()

println("GIVE/FaIR methane representation:")
println("  Globe   : ", give_global_total)
println("  EU27    : ", give_eu27_total)
println("  Germany : ", give_deu_total)

println()

println("GIVE / MOMM RATIOS")
println("==================")

println(
    "  Globe   : ",
    give_global_total / legacy_global_total
)

println(
    "  EU27    : ",
    give_eu27_total / legacy_eu27_total
)

println(
    "  Germany : ",
    give_deu_total / legacy_deu_total
)

println()

println("ATMOSPHERIC RESPONSE CHECK")
println("==========================")
println("year | GIVE delta ppb | MOMM reference ppb | GIVE scale | legacy scale")

for year in 2020:2035

    idx = findfirst(==(year), years)

    println(
        year, " | ",
        give_delta_2020_2100[idx], " | ",
        reference_methane_delta_ppb(year), " | ",
        give_scales[idx], " | ",
        legacy_scales[idx]
    )
end