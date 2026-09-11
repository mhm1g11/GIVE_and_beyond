"""
Export the final GLLEX-ready global GHG damage factors.

This script does NOT run GIVE or any Monte Carlo simulations.

It reads the completed reduced-form damage-factor summaries for:

    CO2:
        2024
        2025

    CH4:
        2024
        2025

and writes one compact external input table:

    research/outputs/gllex_global_damage_factors.csv

Headline metrics:

    CO2:
        total_monetised

    CH4:
        extended_total_monetised

The output contains:

    year
    gas
    mean
    median
    p05
    p95
    unit
    geography
    metric
    n_trials
    price_basis

All values are expected discounted GLOBAL societal damages in 2026 USD
per tonne of the respective gas.

GLLEX should apply these factors directly to physical gas emissions:

    damage =
        tonnes_CO2 * CO2_damage_factor
        +
        tonnes_CH4 * CH4_damage_factor

Methane must NOT first be converted to CO2e.
"""

using FileIO
using CSVFiles
using DataFrames


# ================================================================
# Paths
# ================================================================

const OUTPUT_DIR = normpath(
    joinpath(
        @__DIR__,
        "..",
        "outputs"
    )
)

const CO2_SUMMARY_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_co2_damage_factors_summary.csv"
)

const CH4_2024_SUMMARY_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_ch4_2024_damage_factors_summary.csv"
)

const CH4_2025_PLUS_SUMMARY_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_ch4_damage_factors_summary.csv"
)

const FINAL_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "gllex_global_damage_factors.csv"
)


# ================================================================
# Methodological choices
# ================================================================

const TARGET_YEARS = [
    2024,
    2025
]

const TARGET_GEOGRAPHY = "globe"

const CO2_HEADLINE_METRIC =
    "total_monetised"

const CH4_HEADLINE_METRIC =
    "extended_total_monetised"

const EXPECTED_N_TRIALS =
    100


# ================================================================
# Helpers
# ================================================================

function require_file(
    path::String
)

    isfile(path) ||
        error(
            "Required input file not found: $path"
        )
end


function require_columns(
    df::DataFrame,
    required::Vector{Symbol},
    label::String
)

    available =
        Symbol.(
            names(df)
        )

    missing_columns =
        setdiff(
            required,
            available
        )

    isempty(
        missing_columns
    ) ||
        error(
            "$label is missing required columns: " *
            join(
                string.(
                    missing_columns
                ),
                ", "
            )
        )
end


function statistic_value(
    df::DataFrame,
    statistic::String,
    value_column::Symbol
)

    rows =
        df[
            String.(df.statistic) .==
            statistic,
            :
        ]

    nrow(rows) ==
        1 ||
        error(
            "Expected exactly one '$statistic' row, " *
            "found $(nrow(rows))."
        )

    return Float64(
        rows[
            1,
            value_column
        ]
    )
end


# ================================================================
# Load source files
# ================================================================

println()
println(
    "BUILDING FINAL GLLEX GLOBAL DAMAGE FACTOR TABLE"
)

println(
    "==============================================="
)

println()


for path in [
    CO2_SUMMARY_PATH,
    CH4_2024_SUMMARY_PATH,
    CH4_2025_PLUS_SUMMARY_PATH
]

    require_file(
        path
    )
end


co2 =
    DataFrame(
        load(
            CO2_SUMMARY_PATH
        )
    )

ch4_2024 =
    DataFrame(
        load(
            CH4_2024_SUMMARY_PATH
        )
    )

ch4_2025_plus =
    DataFrame(
        load(
            CH4_2025_PLUS_SUMMARY_PATH
        )
    )


# ================================================================
# Validate schemas
# ================================================================

require_columns(
    co2,
    [
        :gas,
        :pulse_year,
        :geography,
        :metric,
        :statistic,
        :value_usd2026_per_t_co2,
        :current_unit,
        :n_trials,
        :price_basis
    ],
    "CO2 summary"
)


require_columns(
    ch4_2024,
    [
        :gas,
        :pulse_year,
        :geography,
        :metric,
        :statistic,
        :value_usd2026_per_t_ch4,
        :current_unit,
        :n_trials,
        :price_basis
    ],
    "CH4 2024 summary"
)


require_columns(
    ch4_2025_plus,
    [
        :gas,
        :pulse_year,
        :geography,
        :metric,
        :statistic,
        :value_usd2026_per_t_ch4,
        :current_unit,
        :n_trials,
        :price_basis
    ],
    "CH4 2025+ summary"
)


# ================================================================
# Final output table
# ================================================================

output = DataFrame(
    year = Int[],
    gas = String[],

    mean = Float64[],
    median = Float64[],
    p05 = Float64[],
    p95 = Float64[],

    unit = String[],
    geography = String[],
    metric = String[],

    n_trials = Int[],

    price_basis = String[]
)


# ================================================================
# CO2
# ================================================================

for year in TARGET_YEARS

    subset =
        co2[
            (co2.pulse_year .== year) .&
            (String.(co2.geography) .== TARGET_GEOGRAPHY) .&
            (String.(co2.metric) .== CO2_HEADLINE_METRIC),
            :
        ]

    nrow(subset) ==
        4 ||
        error(
            "Expected 4 CO2 summary rows for $year, " *
            "found $(nrow(subset))."
        )

    n_trials =
        unique(
            Int.(
                subset.n_trials
            )
        )

    length(n_trials) ==
        1 ||
        error(
            "CO2 $year has inconsistent trial counts."
        )

    n_trials[1] ==
        EXPECTED_N_TRIALS ||
        error(
            "CO2 $year expected $EXPECTED_N_TRIALS trials, " *
            "found $(n_trials[1])."
        )

    units =
        unique(
            String.(
                subset.current_unit
            )
        )

    length(units) ==
        1 ||
        error(
            "CO2 $year has inconsistent units."
        )

    price_bases =
        unique(
            String.(
                subset.price_basis
            )
        )

    length(price_bases) ==
        1 ||
        error(
            "CO2 $year has inconsistent price bases."
        )

    push!(
        output,
        (
            year,

            "CO2",

            statistic_value(
                subset,
                "mean",
                :value_usd2026_per_t_co2
            ),

            statistic_value(
                subset,
                "median",
                :value_usd2026_per_t_co2
            ),

            statistic_value(
                subset,
                "p05",
                :value_usd2026_per_t_co2
            ),

            statistic_value(
                subset,
                "p95",
                :value_usd2026_per_t_co2
            ),

            units[1],

            TARGET_GEOGRAPHY,

            CO2_HEADLINE_METRIC,

            n_trials[1],

            price_bases[1]
        )
    )
end


# ================================================================
# CH4 2024
# ================================================================

subset =
    ch4_2024[
        (ch4_2024.pulse_year .== 2024) .&
        (String.(ch4_2024.geography) .== TARGET_GEOGRAPHY) .&
        (String.(ch4_2024.metric) .== CH4_HEADLINE_METRIC),
        :
    ]

nrow(subset) ==
    4 ||
    error(
        "Expected 4 CH4 summary rows for 2024, " *
        "found $(nrow(subset))."
    )

n_trials =
    unique(
        Int.(
            subset.n_trials
        )
    )

length(n_trials) ==
    1 ||
    error(
        "CH4 2024 has inconsistent trial counts."
    )

n_trials[1] ==
    EXPECTED_N_TRIALS ||
    error(
        "CH4 2024 expected $EXPECTED_N_TRIALS trials, " *
        "found $(n_trials[1])."
    )

units =
    unique(
        String.(
            subset.current_unit
        )
    )

length(units) ==
    1 ||
    error(
        "CH4 2024 has inconsistent units."
    )

price_bases =
    unique(
        String.(
            subset.price_basis
        )
    )

length(price_bases) ==
    1 ||
    error(
        "CH4 2024 has inconsistent price bases."
    )

push!(
    output,
    (
        2024,

        "CH4",

        statistic_value(
            subset,
            "mean",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "median",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "p05",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "p95",
            :value_usd2026_per_t_ch4
        ),

        units[1],

        TARGET_GEOGRAPHY,

        CH4_HEADLINE_METRIC,

        n_trials[1],

        price_bases[1]
    )
)


# ================================================================
# CH4 2025
# ================================================================

subset =
    ch4_2025_plus[
        (ch4_2025_plus.pulse_year .== 2025) .&
        (String.(ch4_2025_plus.geography) .== TARGET_GEOGRAPHY) .&
        (String.(ch4_2025_plus.metric) .== CH4_HEADLINE_METRIC),
        :
    ]

nrow(subset) ==
    4 ||
    error(
        "Expected 4 CH4 summary rows for 2025, " *
        "found $(nrow(subset))."
    )

n_trials =
    unique(
        Int.(
            subset.n_trials
        )
    )

length(n_trials) ==
    1 ||
    error(
        "CH4 2025 has inconsistent trial counts."
    )

n_trials[1] ==
    EXPECTED_N_TRIALS ||
    error(
        "CH4 2025 expected $EXPECTED_N_TRIALS trials, " *
        "found $(n_trials[1])."
    )

units =
    unique(
        String.(
            subset.current_unit
        )
    )

length(units) ==
    1 ||
    error(
        "CH4 2025 has inconsistent units."
    )

price_bases =
    unique(
        String.(
            subset.price_basis
        )
    )

length(price_bases) ==
    1 ||
    error(
        "CH4 2025 has inconsistent price bases."
    )

push!(
    output,
    (
        2025,

        "CH4",

        statistic_value(
            subset,
            "mean",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "median",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "p05",
            :value_usd2026_per_t_ch4
        ),

        statistic_value(
            subset,
            "p95",
            :value_usd2026_per_t_ch4
        ),

        units[1],

        TARGET_GEOGRAPHY,

        CH4_HEADLINE_METRIC,

        n_trials[1],

        price_bases[1]
    )
)


# ================================================================
# Final QA
# ================================================================

sort!(
    output,
    [
        :year,
        :gas
    ]
)


nrow(output) ==
    4 ||
    error(
        "Final GLLEX table must contain exactly 4 rows."
    )


expected_pairs =
    Set(
        [
            (2024, "CO2"),
            (2024, "CH4"),
            (2025, "CO2"),
            (2025, "CH4")
        ]
    )


actual_pairs =
    Set(
        (
            Int(row.year),
            String(row.gas)
        )
        for row in eachrow(
            output
        )
    )


actual_pairs ==
    expected_pairs ||
    error(
        "Final year/gas combinations are incorrect."
    )


all(
    output.p05 .<=
    output.median
) ||
    error(
        "Some p05 values exceed the median."
    )


all(
    output.median .<=
    output.p95
) ||
    error(
        "Some median values exceed p95."
    )


all(
    isfinite,
    output.mean
) ||
    error(
        "Non-finite mean values detected."
    )


all(
    isfinite,
    output.median
) ||
    error(
        "Non-finite median values detected."
    )


all(
    isfinite,
    output.p05
) ||
    error(
        "Non-finite p05 values detected."
    )


all(
    isfinite,
    output.p95
) ||
    error(
        "Non-finite p95 values detected."
    )


println(
    "Final row-count QA: PASS"
)

println(
    "Year/gas coverage QA: PASS"
)

println(
    "Uncertainty-order QA: PASS"
)

println(
    "Finite-value QA: PASS"
)


# ================================================================
# Save
# ================================================================

save(
    FINAL_OUTPUT_PATH,
    output
)


# ================================================================
# Console output
# ================================================================

println()
println(
    "FINAL GLLEX GLOBAL DAMAGE FACTORS"
)

println(
    "================================="
)

println()


for row in eachrow(
    output
)

    println(
        row.year,
        " ",
        row.gas
    )

    println(
        "  Mean:   ",
        round(
            row.mean,
            digits = 2
        ),
        " ",
        row.unit
    )

    println(
        "  Median: ",
        round(
            row.median,
            digits = 2
        ),
        " ",
        row.unit
    )

    println(
        "  p05:    ",
        round(
            row.p05,
            digits = 2
        ),
        " ",
        row.unit
    )

    println(
        "  p95:    ",
        round(
            row.p95,
            digits = 2
        ),
        " ",
        row.unit
    )

    println()
end


println(
    "Saved:"
)

println(
    "  ",
    FINAL_OUTPUT_PATH
)

println()

println(
    "GLLEX application:"
)

println(
    "  total global societal damage ="
)

println(
    "      tonnes CO2 × CO2 factor"
)

println(
    "    + tonnes CH4 × CH4 factor"
)

println()

println(
    "Use the mean as the central estimate."
)

println(
    "Retain p05-p95 as the uncertainty range."
)

println()

println(
    "Do not convert CH4 to CO2e before applying the damage factors."
)