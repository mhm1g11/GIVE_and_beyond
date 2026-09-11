"""
Build reduced-form global monetary CO2 damage factors for external use.

This script RUNS MimiGIVE Monte Carlo SCC calculations.

It uses the same explicit aligned Monte Carlo design as the methane
analysis:

    research/inputs/mc_trial_design.csv

Only the two years currently represented in GLLEX are calculated:

    2024
    2025

For each pulse year, the calculation uses the same:

    RFF socioeconomic trial IDs
    FaIR parameter-set IDs
    Monte Carlo seed
    discounting assumptions
    impact horizon

Only GLOBAL damage factors are required for GLLEX.

Country-level and EU27 disaggregated damages are deliberately NOT calculated.

Outputs:

    research/outputs/reduced_form_co2_damage_factors_trials.csv
    research/outputs/reduced_form_co2_damage_factors_summary.csv

Metrics:

    total_monetised
    total_monetised_excl_agriculture
    temperature_mortality_monetised
    agriculture_monetised
    energy_monetised
    slr_monetised

The headline GLLEX CO2 damage factor is:

    total_monetised

Unlike methane, no separate ozone-mortality extension is added to CO2.

Monetary values are exported in:

    USD2005 per tonne CO2
    USD2026 per tonne CO2

Current-dollar conversion uses CPI-U:

    2005 annual average: 195.3
    August 2026:         334.980

The intended interpretation is:

    expected discounted global societal damage
    per tonne CO2 emitted
"""

using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics
using Random


# ================================================================
# Project configuration
# ================================================================

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)


# ================================================================
# External CO2 calculation settings
# ================================================================

const EXTERNAL_GAS = :CO2

const EXTERNAL_PULSE_YEARS = [
    2024,
    2025
]

const MC_SEED = 20260908

const TARGET_GEOGRAPHY = "globe"

const HEADLINE_METRIC =
    "total_monetised"


# ================================================================
# Current-dollar conversion
# ================================================================

const CPI_2005_ANNUAL_AVERAGE =
    195.3

const CPI_2026_CURRENT =
    334.980

const CPI_UPRATING_FACTOR =
    CPI_2026_CURRENT /
    CPI_2005_ANNUAL_AVERAGE

const ORIGINAL_UNIT =
    "USD2005_per_t_CO2"

const CURRENT_UNIT =
    "USD2026_per_t_CO2"

const PRICE_BASIS =
    "August 2026 CPI-U, U.S. city average, all items"

const CPI_SOURCE =
    "U.S. Bureau of Labor Statistics"


# ================================================================
# Explicit aligned Monte Carlo trial design
# ================================================================

const TRIAL_DESIGN_PATH = joinpath(
    INPUT_DIR,
    "mc_trial_design.csv"
)

trial_design =
    DataFrame(
        load(
            TRIAL_DESIGN_PATH
        )
    )


function as_int(x)

    if x isa Integer
        return Int(x)
    end

    return parse(
        Int,
        strip(
            string(x)
        )
    )
end


trial_design.trialnum =
    as_int.(
        trial_design.trialnum
    )

trial_design.rffsp_id =
    as_int.(
        trial_design.rffsp_id
    )

trial_design.fair_parameter_set_id =
    as_int.(
        trial_design.fair_parameter_set_id
    )

sort!(
    trial_design,
    :trialnum
)

const N_TRIALS =
    nrow(
        trial_design
    )

const RFFSP_IDS =
    collect(
        trial_design.rffsp_id
    )

const FAIR_IDS =
    collect(
        trial_design.fair_parameter_set_id
    )


trial_design.trialnum ==
    collect(
        1:N_TRIALS
    ) ||
    error(
        "mc_trial_design.csv must contain consecutive trial numbers 1:N."
    )


# ================================================================
# Output files
# ================================================================

const TRIAL_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_co2_damage_factors_trials.csv"
)

const SUMMARY_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_co2_damage_factors_summary.csv"
)

const CO2_RUN_DIR = joinpath(
    GIVE_RUN_DIR,
    "external_co2"
)

mkpath(
    OUTPUT_DIR
)

mkpath(
    GIVE_RUN_DIR
)

mkpath(
    CO2_RUN_DIR
)


# ================================================================
# Helpers
# ================================================================

function official_global_scc(
    result,
    sector::Symbol
)

    key = (
        region = :globe,
        sector = sector,
        dr_label = DISCOUNT_LABEL,
        prtp = PRTP,
        eta = ETA,
        ew = nothing,
        ew_norm_region = nothing
    )

    raw_values =
        result[
            :scc
        ][
            key
        ].sccs

    values = [
        ismissing(x) ?
            NaN :
            Float64(x)
        for x in raw_values
    ]

    length(values) ==
        N_TRIALS ||
        error(
            "Expected $N_TRIALS SCC values for sector $sector, " *
            "found $(length(values))."
        )

    all(
        isfinite,
        values
    ) ||
        error(
            "Non-finite SCC values found for sector $sector."
        )

    return values
end


function add_trial_rows!(
    output::DataFrame,
    pulse_year::Int,
    metric::String,
    values
)

    length(values) ==
        N_TRIALS ||
        error(
            "Expected $N_TRIALS trial values for " *
            "$pulse_year / $metric."
        )

    for trial in eachindex(
        values
    )

        value_2005 =
            Float64(
                values[
                    trial
                ]
            )

        value_2026 =
            value_2005 *
            CPI_UPRATING_FACTOR

        push!(
            output,
            (
                "CO2",

                pulse_year,

                trial,

                Int(
                    trial_design.rffsp_id[
                        trial
                    ]
                ),

                Int(
                    trial_design.fair_parameter_set_id[
                        trial
                    ]
                ),

                TARGET_GEOGRAPHY,

                metric,

                value_2005,

                value_2026,

                ORIGINAL_UNIT,

                CURRENT_UNIT
            )
        )
    end
end


function summarize_factors(
    df::DataFrame
)

    result = DataFrame(
        gas = String[],
        pulse_year = Int[],
        geography = String[],
        metric = String[],
        statistic = String[],

        value_usd2005_per_t_co2 =
            Float64[],

        value_usd2026_per_t_co2 =
            Float64[],

        original_unit = String[],
        current_unit = String[],

        n_trials = Int[],

        cpi_u_2005 = Float64[],
        cpi_u_2026 = Float64[],
        cpi_uprating_factor = Float64[],

        price_basis = String[],
        cpi_source = String[]
    )


    grouped =
        groupby(
            df,
            [
                :gas,
                :pulse_year,
                :geography,
                :metric
            ]
        )


    for group in grouped

        values_2005 =
            Float64.(
                group.value_usd2005_per_t_co2
            )

        length(values_2005) ==
            N_TRIALS ||
            error(
                "Expected $N_TRIALS values for " *
                "$(group.pulse_year[1]) / $(group.metric[1])."
            )

        stats = [
            (
                "mean",
                mean(
                    values_2005
                )
            ),

            (
                "median",
                median(
                    values_2005
                )
            ),

            (
                "p05",
                quantile(
                    values_2005,
                    0.05
                )
            ),

            (
                "p95",
                quantile(
                    values_2005,
                    0.95
                )
            )
        ]


        for (
            statistic,
            value_2005
        ) in stats

            value_2026 =
                value_2005 *
                CPI_UPRATING_FACTOR

            push!(
                result,
                (
                    String(
                        group.gas[1]
                    ),

                    Int(
                        group.pulse_year[1]
                    ),

                    String(
                        group.geography[1]
                    ),

                    String(
                        group.metric[1]
                    ),

                    statistic,

                    Float64(
                        value_2005
                    ),

                    Float64(
                        value_2026
                    ),

                    ORIGINAL_UNIT,

                    CURRENT_UNIT,

                    length(
                        values_2005
                    ),

                    CPI_2005_ANNUAL_AVERAGE,

                    CPI_2026_CURRENT,

                    CPI_UPRATING_FACTOR,

                    PRICE_BASIS,

                    CPI_SOURCE
                )
            )
        end
    end


    sort!(
        result,
        [
            :pulse_year,
            :metric,
            :statistic
        ]
    )

    return result
end


# ================================================================
# Main trial-level table
# ================================================================

all_trials = DataFrame(
    gas = String[],
    pulse_year = Int[],
    trialnum = Int[],
    rffsp_id = Int[],
    fair_parameter_set_id = Int[],
    geography = String[],
    metric = String[],

    value_usd2005_per_t_co2 =
        Float64[],

    value_usd2026_per_t_co2 =
        Float64[],

    original_unit = String[],
    current_unit = String[]
)


# ================================================================
# Console header
# ================================================================

println()
println(
    "BUILDING GLOBAL CO2 DAMAGE FACTORS FOR EXTERNAL USE"
)

println(
    "==================================================="
)

println()

println(
    "Gas:                 ",
    EXTERNAL_GAS
)

println(
    "Geography:           ",
    TARGET_GEOGRAPHY
)

println(
    "Pulse years:         ",
    join(
        EXTERNAL_PULSE_YEARS,
        ", "
    )
)

println(
    "Impact horizon:      ",
    IMPACT_HORIZON
)

println(
    "Trials per year:     ",
    N_TRIALS
)

println(
    "Total trial draws:   ",
    N_TRIALS *
    length(
        EXTERNAL_PULSE_YEARS
    )
)

println(
    "Monte Carlo seed:    ",
    MC_SEED
)

println(
    "Disaggregated output: OFF"
)

println(
    "Sectoral output:      ON"
)

println()

println(
    "2005 -> 2026 CPI factor: ",
    round(
        CPI_UPRATING_FACTOR,
        digits = 6
    )
)

println()


# ================================================================
# Run each CO2 pulse year
# ================================================================

for pulse_year in EXTERNAL_PULSE_YEARS

    println()
    println(
        "================================================"
    )

    println(
        "CO2 PULSE YEAR ",
        pulse_year
    )

    println(
        "================================================"
    )


    run_dir = joinpath(
        CO2_RUN_DIR,
        "pulse_$(pulse_year)"
    )


    if isdir(
        run_dir
    )

        rm(
            run_dir;
            recursive = true,
            force = true
        )
    end


    # ------------------------------------------------------------
    # Reset seed so all remaining stochastic GIVE parameters remain
    # aligned across pulse years.
    #
    # RFF socioeconomic and FaIR parameter-set IDs are explicitly
    # fixed by mc_trial_design.csv.
    # ------------------------------------------------------------

    Random.seed!(
        MC_SEED
    )


    println(
        "Running ",
        N_TRIALS,
        "-trial global CO2 SCC calculation..."
    )


    result =
        MimiGIVE.compute_scc(
            year = pulse_year,

            last_year =
                IMPACT_HORIZON,

            gas =
                EXTERNAL_GAS,

            n =
                N_TRIALS,

            discount_rates =
                DISCOUNT_RATES,

            fair_parameter_set =
                :deterministic,

            fair_parameter_set_ids =
                FAIR_IDS,

            rffsp_sampling =
                :deterministic,

            rffsp_sampling_ids =
                RFFSP_IDS,

            compute_sectoral_values =
                true,

            compute_disaggregated_values =
                false,

            save_cpc =
                false,

            output_dir =
                run_dir
        )


    # ============================================================
    # Global CO2 damages
    # ============================================================

    global_total =
        official_global_scc(
            result,
            :total
        )

    global_mortality =
        official_global_scc(
            result,
            :cromar_mortality
        )

    global_agriculture =
        official_global_scc(
            result,
            :agriculture
        )

    global_energy =
        official_global_scc(
            result,
            :energy
        )

    global_slr =
        official_global_scc(
            result,
            :slr
        )


    global_total_excl_agriculture =
        global_mortality .+
        global_energy .+
        global_slr


    # ============================================================
    # Add trial rows
    # ============================================================

    add_trial_rows!(
        all_trials,
        pulse_year,
        "total_monetised",
        global_total
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "total_monetised_excl_agriculture",
        global_total_excl_agriculture
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "temperature_mortality_monetised",
        global_mortality
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "agriculture_monetised",
        global_agriculture
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "energy_monetised",
        global_energy
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "slr_monetised",
        global_slr
    )


    # ============================================================
    # Pulse-year console summary
    # ============================================================

    println()

    println(
        "Mean global CO2 damage factors for ",
        pulse_year,
        ":"
    )

    println(
        "  Total: ",
        round(
            mean(
                global_total
            ),
            digits = 3
        ),
        " USD2005/tCO2"
    )

    println(
        "  Total: ",
        round(
            mean(
                global_total
            ) *
            CPI_UPRATING_FACTOR,
            digits = 3
        ),
        " USD2026/tCO2"
    )

    println(
        "  Temperature mortality: ",
        round(
            mean(
                global_mortality
            ) *
            CPI_UPRATING_FACTOR,
            digits = 3
        ),
        " USD2026/tCO2"
    )

    println(
        "  Agriculture: ",
        round(
            mean(
                global_agriculture
            ) *
            CPI_UPRATING_FACTOR,
            digits = 3
        ),
        " USD2026/tCO2"
    )

    println(
        "  Energy: ",
        round(
            mean(
                global_energy
            ) *
            CPI_UPRATING_FACTOR,
            digits = 3
        ),
        " USD2026/tCO2"
    )

    println(
        "  Sea-level rise: ",
        round(
            mean(
                global_slr
            ) *
            CPI_UPRATING_FACTOR,
            digits = 3
        ),
        " USD2026/tCO2"
    )


    GC.gc()
end


# ================================================================
# Sort trial-level library
# ================================================================

sort!(
    all_trials,
    [
        :pulse_year,
        :metric,
        :trialnum
    ]
)


# ================================================================
# Final trial-design QA
# ================================================================

println()
println(
    "EXPLICIT TRIAL-DESIGN QA"
)

println(
    "========================"
)


for trialnum in 1:N_TRIALS

    rows =
        filter(
            row ->
                row.trialnum ==
                trialnum,
            all_trials
        )

    rff_ids =
        unique(
            rows.rffsp_id
        )

    fair_ids =
        unique(
            rows.fair_parameter_set_id
        )


    length(
        rff_ids
    ) == 1 ||
        error(
            "Trial $trialnum has multiple RFF IDs."
        )


    length(
        fair_ids
    ) == 1 ||
        error(
            "Trial $trialnum has multiple FaIR IDs."
        )


    rff_ids[1] ==
        trial_design.rffsp_id[
            trialnum
        ] ||
        error(
            "Trial $trialnum RFF ID does not match mc_trial_design.csv."
        )


    fair_ids[1] ==
        trial_design.fair_parameter_set_id[
            trialnum
        ] ||
        error(
            "Trial $trialnum FaIR ID does not match mc_trial_design.csv."
        )
end


println(
    "All ",
    N_TRIALS,
    " trial mappings: PASS"
)


# ================================================================
# Row-count QA
# ================================================================

const N_METRICS = 6

expected_trial_rows =
    length(
        EXTERNAL_PULSE_YEARS
    ) *
    N_TRIALS *
    N_METRICS


nrow(
    all_trials
) ==
    expected_trial_rows ||
    error(
        "Expected $expected_trial_rows trial rows, " *
        "found $(nrow(all_trials))."
    )


println(
    "Trial row count: PASS (",
    nrow(
        all_trials
    ),
    " rows)"
)


# ================================================================
# Current-dollar conversion QA
# ================================================================

converted_check =
    all_trials.value_usd2005_per_t_co2 .*
    CPI_UPRATING_FACTOR


maximum(
    abs.(
        converted_check .-
        all_trials.value_usd2026_per_t_co2
    )
) <
    1e-8 ||
    error(
        "USD2026 conversion QA failed."
    )


println(
    "Current-dollar conversion: PASS"
)


# ================================================================
# Summary statistics
# ================================================================

summary =
    summarize_factors(
        all_trials
    )


expected_summary_rows =
    length(
        EXTERNAL_PULSE_YEARS
    ) *
    N_METRICS *
    4


nrow(
    summary
) ==
    expected_summary_rows ||
    error(
        "Expected $expected_summary_rows summary rows, " *
        "found $(nrow(summary))."
    )


# ================================================================
# Save
# ================================================================

save(
    TRIAL_OUTPUT_PATH,
    all_trials
)

save(
    SUMMARY_OUTPUT_PATH,
    summary
)


# ================================================================
# Final console summary
# ================================================================

println()
println(
    "GLOBAL CO2 DAMAGE FACTOR BUILD COMPLETE"
)

println(
    "======================================="
)

println()

println(
    "Trial rows:   ",
    nrow(
        all_trials
    )
)

println(
    "Summary rows: ",
    nrow(
        summary
    )
)

println()

println(
    "Saved:"
)

println(
    "  ",
    TRIAL_OUTPUT_PATH
)

println(
    "  ",
    SUMMARY_OUTPUT_PATH
)

println()

println(
    "Pulse years:"
)

println(
    "  ",
    join(
        EXTERNAL_PULSE_YEARS,
        ", "
    )
)

println()

println(
    "Headline GLLEX metric:"
)

println(
    "  ",
    HEADLINE_METRIC
)

println()

println(
    "Interpretation:"
)

println(
    "  expected discounted global societal damage per tonne CO2 emitted"
)

println()

println(
    "Current-dollar unit:"
)

println(
    "  ",
    CURRENT_UNIT
)

println()

println(
    "Price basis:"
)

println(
    "  ",
    PRICE_BASIS
)

println()

println(
    "IMPORTANT"
)

println(
    "========="
)

println(
    "This calculation uses exactly the same explicit RFF socioeconomic " *
    "and FaIR parameter-set IDs as the methane analysis."
)

println(
    "The same Monte Carlo seed is reset before every pulse-year run so " *
    "remaining stochastic GIVE parameters stay aligned across 2024 and 2025."
)

println(
    "Only global damages are calculated. Country and EU27 disaggregated " *
    "outputs are intentionally disabled."
)

println(
    "These are 100-trial estimates and should retain their uncertainty " *
    "range when used in GLLEX."
)