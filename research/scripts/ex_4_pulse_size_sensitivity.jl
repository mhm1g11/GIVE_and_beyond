"""
Test whether reduced-form CO2 and CH4 damage factors remain approximately
linear over emission pulse sizes relevant for GLLEX.

This is a methodological sensitivity test only.

It does NOT run the 100-trial Monte Carlo design.

Instead, it holds the deterministic GIVE model configuration fixed and
varies only the size of the emissions pulse.

The test covers:

1. GIVE global CO2 damages
2. GIVE global CH4 climate damages
3. Methane-induced ozone mortality response

Pulse year:

    2025

CO2 pulse sizes are specified in GIVE's native pulse_size units:

    1.0 = 1 Gt C
        = approximately 3.667 Gt CO2

Tested CO2 pulse sizes:

    0.001 Gt C  ≈    3.67 Mt CO2
    0.01  Gt C  ≈   36.67 Mt CO2
    0.1   Gt C  ≈  366.67 Mt CO2
    0.3   Gt C  ≈ 1,100.00 Mt CO2
    1.0   Gt C  ≈ 3,666.67 Mt CO2

CH4 pulse sizes are specified directly in Mt CH4:

    0.01 Mt CH4
    0.1  Mt CH4
    1.0  Mt CH4
    5.0  Mt CH4
    10.0 Mt CH4

For GIVE, compute_scc already normalizes results to USD2005 per tonne
of the specified gas.

For the ozone extension, total ozone deaths are explicitly divided by
the methane pulse size to obtain deaths per Mt CH4.

If the normalized result remains stable as the pulse becomes larger,
multiplying a per-tonne damage factor by GLLEX lifecycle emissions is
a defensible linear approximation.

Output:

    research/outputs/pulse_size_sensitivity.csv
"""

using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics


# =====================================================================
# Project modules and configuration
# =====================================================================

include(
    joinpath(
        @__DIR__,
        "..",
        "src",
        "MethaneOzoneMortality.jl"
    )
)

using .MethaneOzoneMortality

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)


# =====================================================================
# Settings
# =====================================================================

const TEST_YEAR = 2025

const CO2_PULSE_SIZES_GTC = [
    0.001,
    0.01,
    0.1,
    0.3,
    1.0
]

const CH4_PULSE_SIZES_MT = [
    0.01,
    0.1,
    1.0,
    5.0,
    10.0
]


# =====================================================================
# Paths
# =====================================================================

const MOMM_ROOT = normpath(
    joinpath(
        @__DIR__,
        "..",
        "external",
        "MOMM-RFT"
    )
)

const OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "pulse_size_sensitivity.csv"
)

mkpath(
    OUTPUT_DIR
)


# =====================================================================
# Output table
# =====================================================================

results = DataFrame(
    gas = String[],
    response = String[],
    pulse_year = Int[],

    pulse_size_native = Float64[],
    pulse_unit_native = String[],

    pulse_mt_gas = Float64[],

    normalized_value = Float64[],
    normalized_unit = String[],

    reference_value = Float64[],
    relative_difference_pct = Float64[]
)


# =====================================================================
# Helper: deterministic GIVE SCC
# =====================================================================

function deterministic_give_scc(
    gas::Symbol,
    pulse_size::Float64
)

    result =
        MimiGIVE.compute_scc(
            year =
                TEST_YEAR,

            last_year =
                IMPACT_HORIZON,

            gas =
                gas,

            prtp =
                PRTP,

            eta =
                ETA,

            pulse_size =
                pulse_size
        )

    return Float64(
        result
    )
end


# =====================================================================
# 1. CO2 pulse-size sensitivity
# =====================================================================

println()
println(
    "PULSE-SIZE SENSITIVITY TEST"
)

println(
    "==========================="
)

println()

println(
    "Pulse year: ",
    TEST_YEAR
)

println(
    "Impact horizon: ",
    IMPACT_HORIZON
)

println()

println(
    "STEP 1: CO2 GIVE damage response"
)

println(
    "--------------------------------"
)

co2_values =
    Float64[]


for pulse_size in CO2_PULSE_SIZES_GTC

    pulse_mt_co2 =
        pulse_size *
        1000.0 *
        44.0 /
        12.0

    println()
    println(
        "CO2 pulse: ",
        pulse_size,
        " Gt C = ",
        round(
            pulse_mt_co2,
            digits = 3
        ),
        " Mt CO2"
    )

    value =
        deterministic_give_scc(
            :CO2,
            pulse_size
        )

    push!(
        co2_values,
        value
    )

    println(
        "  Normalized GIVE damage: ",
        round(
            value,
            digits = 6
        ),
        " USD2005/tCO2"
    )
end


co2_reference =
    first(
        co2_values
    )


for (
    i,
    pulse_size
) in enumerate(
    CO2_PULSE_SIZES_GTC
)

    pulse_mt_co2 =
        pulse_size *
        1000.0 *
        44.0 /
        12.0

    relative_difference =
        100.0 *
        (
            co2_values[i] /
            co2_reference -
            1.0
        )

    push!(
        results,
        (
            "CO2",
            "GIVE_total_damage",
            TEST_YEAR,

            pulse_size,
            "GtC",

            pulse_mt_co2,

            co2_values[i],
            "USD2005_per_t_CO2",

            co2_reference,
            relative_difference
        )
    )
end


# =====================================================================
# 2. CH4 GIVE climate-damage pulse sensitivity
# =====================================================================

println()
println(
    "STEP 2: CH4 GIVE climate-damage response"
)

println(
    "----------------------------------------"
)

ch4_give_values =
    Float64[]


for pulse_size in CH4_PULSE_SIZES_MT

    println()
    println(
        "CH4 pulse: ",
        pulse_size,
        " Mt CH4"
    )

    value =
        deterministic_give_scc(
            :CH4,
            pulse_size
        )

    push!(
        ch4_give_values,
        value
    )

    println(
        "  Normalized GIVE damage: ",
        round(
            value,
            digits = 6
        ),
        " USD2005/tCH4"
    )
end


ch4_give_reference =
    first(
        ch4_give_values
    )


for (
    i,
    pulse_size
) in enumerate(
    CH4_PULSE_SIZES_MT
)

    relative_difference =
        100.0 *
        (
            ch4_give_values[i] /
            ch4_give_reference -
            1.0
        )

    push!(
        results,
        (
            "CH4",
            "GIVE_climate_damage",
            TEST_YEAR,

            pulse_size,
            "MtCH4",

            pulse_size,

            ch4_give_values[i],
            "USD2005_per_t_CH4",

            ch4_give_reference,
            relative_difference
        )
    )
end


# =====================================================================
# 3. Load McDuffie ozone-health reference
# =====================================================================

println()
println(
    "STEP 3: CH4 ozone-response sensitivity"
)

println(
    "--------------------------------------"
)

reference =
    load_momm_reference(
        MOMM_ROOT
    )


# =====================================================================
# 4. Ozone response for different methane pulse sizes
# =====================================================================

ozone_values =
    Float64[]


for pulse_size in CH4_PULSE_SIZES_MT

    println()
    println(
        "CH4 ozone pulse: ",
        pulse_size,
        " Mt CH4"
    )


    m =
        MimiGIVE.get_model()


    mm =
        MimiGIVE.get_marginal_model(
            m;
            year =
                TEST_YEAR,

            gas =
                :CH4,

            pulse_size =
                pulse_size
        )


    run(
        mm
    )


    give_years =
        collect(
            dim_keys(
                mm.base,
                :time
            )
        )


    delta_ch4 =
        mm.modified[
            :ch4_cycle,
            :CH₄
        ] .-
        mm.base[
            :ch4_cycle,
            :CH₄
        ]


    years =
        collect(
            2020:
            IMPACT_HORIZON
        )


    indices = [
        findfirst(
            ==(year),
            give_years
        )
        for year in years
    ]


    any(
        isnothing,
        indices
    ) &&
        error(
            "Required year missing from GIVE."
        )


    give_delta = [
        Float64(
            delta_ch4[
                idx
            ]
        )
        for idx in indices
    ]


    methane_scales =
        give_methane_scaling(
            years,
            give_delta
        )


    atmosphere =
        calculate_ozone_deaths(
            reference,
            years,
            methane_scales
        )


    atmosphere =
        filter(
            row ->
                TEST_YEAR <=
                row.year <=
                IMPACT_HORIZON,
            atmosphere
        )


    total_deaths =
        sum(
            Float64.(
                atmosphere.ozone_respiratory_deaths
            )
        )


    deaths_per_mt_ch4 =
        total_deaths /
        pulse_size


    push!(
        ozone_values,
        deaths_per_mt_ch4
    )


    println(
        "  Total ozone deaths: ",
        round(
            total_deaths,
            digits = 6
        )
    )

    println(
        "  Normalized ozone response: ",
        round(
            deaths_per_mt_ch4,
            digits = 6
        ),
        " deaths/Mt CH4"
    )
end


ozone_reference =
    first(
        ozone_values
    )


for (
    i,
    pulse_size
) in enumerate(
    CH4_PULSE_SIZES_MT
)

    relative_difference =
        100.0 *
        (
            ozone_values[i] /
            ozone_reference -
            1.0
        )

    push!(
        results,
        (
            "CH4",
            "ozone_mortality_response",
            TEST_YEAR,

            pulse_size,
            "MtCH4",

            pulse_size,

            ozone_values[i],
            "deaths_per_Mt_CH4",

            ozone_reference,
            relative_difference
        )
    )
end


# =====================================================================
# 5. QA
# =====================================================================

println()
println(
    "QA"
)

println(
    "=="
)

println()


all(
    isfinite,
    results.normalized_value
) ||
    error(
        "Non-finite normalized values detected."
    )


all(
    isfinite,
    results.relative_difference_pct
) ||
    error(
        "Non-finite relative differences detected."
    )


expected_rows =
    length(
        CO2_PULSE_SIZES_GTC
    ) +
    2 *
    length(
        CH4_PULSE_SIZES_MT
    )


nrow(
    results
) ==
    expected_rows ||
    error(
        "Expected $expected_rows rows, " *
        "found $(nrow(results))."
    )


println(
    "Finite-value QA: PASS"
)

println(
    "Row-count QA: PASS (",
    nrow(results),
    " rows)"
)


# =====================================================================
# 6. Summary diagnostics
# =====================================================================

function max_abs_relative_difference(
    df::DataFrame,
    gas::String,
    response::String
)

    subset =
        filter(
            row ->
                row.gas ==
                    gas &&
                row.response ==
                    response,
            df
        )

    return maximum(
        abs.(
            subset.relative_difference_pct
        )
    )
end


co2_max_difference =
    max_abs_relative_difference(
        results,
        "CO2",
        "GIVE_total_damage"
    )


ch4_give_max_difference =
    max_abs_relative_difference(
        results,
        "CH4",
        "GIVE_climate_damage"
    )


ozone_max_difference =
    max_abs_relative_difference(
        results,
        "CH4",
        "ozone_mortality_response"
    )


println()
println(
    "MAXIMUM ABSOLUTE DEVIATION FROM SMALLEST PULSE"
)

println(
    "============================================="
)

println()

println(
    "CO2 GIVE damage: ",
    round(
        co2_max_difference,
        digits = 4
    ),
    "%"
)

println(
    "CH4 GIVE climate damage: ",
    round(
        ch4_give_max_difference,
        digits = 4
    ),
    "%"
)

println(
    "CH4 ozone response: ",
    round(
        ozone_max_difference,
        digits = 4
    ),
    "%"
)


# =====================================================================
# 7. Simple interpretation
# =====================================================================

function interpretation(
    difference::Float64
)

    if difference < 1.0

        return "VERY STABLE (<1%)"

    elseif difference < 5.0

        return "SMALL NONLINEARITY (1-5%)"

    else

        return "MATERIAL PULSE-SIZE SENSITIVITY (>5%)"
    end
end


println()
println(
    "INTERPRETATION"
)

println(
    "=============="
)

println()

println(
    "CO2 GIVE: ",
    interpretation(
        co2_max_difference
    )
)

println(
    "CH4 GIVE: ",
    interpretation(
        ch4_give_max_difference
    )
)

println(
    "CH4 ozone: ",
    interpretation(
        ozone_max_difference
    )
)


# =====================================================================
# 8. Save
# =====================================================================

sort!(
    results,
    [
        :gas,
        :response,
        :pulse_size_native
    ]
)


save(
    OUTPUT_PATH,
    results
)


println()
println(
    "PULSE-SIZE SENSITIVITY TEST COMPLETE"
)

println(
    "===================================="
)

println()

println(
    "Saved:"
)

println(
    "  ",
    OUTPUT_PATH
)

println()

println(
    "This test evaluates whether normalized marginal damages remain " *
    "stable as the emissions pulse increases."
)

println(
    "It is a deterministic structural linearity test, not an " *
    "uncertainty analysis."
)