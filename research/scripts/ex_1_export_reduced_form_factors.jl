"""
Build reduced-form global monetary CH4 damage factors for external use.

This script does NOT run GIVE or any Monte Carlo simulations.

It combines the existing aligned trial-level outputs from:

    research/outputs/monetary_impact_library_trials.csv
    research/outputs/ozone_monetary_impact_library_trials.csv

and exports global-only monetary damage factors to:

    research/outputs/reduced_form_ch4_damage_factors_trials.csv
    research/outputs/reduced_form_ch4_damage_factors_summary.csv

The resulting factor library contains:

1. Existing global GIVE monetised impact metrics
2. Global GIVE climate-total monetary damages
3. Global methane-induced ozone mortality monetary damages
4. Global extended total monetary damages:

       GIVE total climate damages
       + methane-induced ozone mortality damages

The headline GIVE total is explicitly defined as:

    total_monetised

The alternative metric:

    total_monetised_excl_agriculture

is retained as a sensitivity metric but is NOT used to construct the
headline extended total.

Monetary values are exported in two price bases:

    USD2005_per_t_CH4
    USD2026_per_t_CH4

The current-USD conversion uses the U.S. Consumer Price Index for All Urban
Consumers (CPI-U), U.S. city average, all items:

    2005 annual average: 195.3
    August 2026:         334.980

Conversion factor:

    334.980 / 195.3 = 1.715207373...

Source:
U.S. Bureau of Labor Statistics.

August 2026 is the latest available CPI observation as of 11 September 2026.

The intended interpretation of the headline factor is:

    expected discounted GLOBAL societal damage per tonne CH4 emitted

The location of the emission does not determine the geography of damages.
Only global damages are exported for use in the LNG lifecycle dashboard.

Important:
The extended total is calculated within each aligned Monte Carlo trial before
summary statistics are calculated. This preserves the joint RFF socioeconomic
and FaIR climate uncertainty structure.
"""

using FileIO
using CSVFiles
using DataFrames
using Statistics


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

const MONETARY_PATH = joinpath(
    "research",
    "outputs",
    "monetary_impact_library_trials.csv",
)

const OZONE_PATH = joinpath(
    "research",
    "outputs",
    "ozone_monetary_impact_library_trials.csv",
)

const TRIAL_OUTPUT_PATH = joinpath(
    "research",
    "outputs",
    "reduced_form_ch4_damage_factors_trials.csv",
)

const SUMMARY_OUTPUT_PATH = joinpath(
    "research",
    "outputs",
    "reduced_form_ch4_damage_factors_summary.csv",
)


# ---------------------------------------------------------------------------
# Methodological choices
# ---------------------------------------------------------------------------

const GIVE_HEADLINE_TOTAL_METRIC = "total_monetised"
const TARGET_GEOGRAPHY = "globe"

const CPI_2005_ANNUAL_AVERAGE = 195.3
const CPI_2026_CURRENT = 334.980

const CPI_UPRATING_FACTOR =
    CPI_2026_CURRENT / CPI_2005_ANNUAL_AVERAGE

const ORIGINAL_UNIT = "USD2005_per_t_CH4"
const CURRENT_UNIT = "USD2026_per_t_CH4"

const PRICE_BASIS =
    "August 2026 CPI-U, U.S. city average, all items"

const CPI_SOURCE =
    "U.S. Bureau of Labor Statistics"


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

const KEY_COLS = [
    :pulse_year,
    :trialnum,
    :rffsp_id,
    :fair_parameter_set_id,
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function require_columns(
    df::DataFrame,
    required::Vector{Symbol},
    label::String,
)
    available = Symbol.(names(df))
    missing_cols = setdiff(required, available)

    isempty(missing_cols) || error(
        "$label is missing required columns: " *
        join(string.(missing_cols), ", ")
    )
end


function assert_unique(
    df::DataFrame,
    cols::Vector{Symbol},
    label::String,
)
    unique_rows = unique(select(df, cols))

    nrow(unique_rows) == nrow(df) || error(
        "$label contains duplicate rows for key: " *
        join(string.(cols), ", ")
    )
end


function make_factor_rows(
    base::DataFrame,
    metric::String,
    values,
    source::String,
)
    n = nrow(base)

    values_2005 = Float64.(values)
    values_2026 = values_2005 .* CPI_UPRATING_FACTOR

    return DataFrame(
        gas = fill("CH4", n),
        pulse_year = Int.(base.pulse_year),
        trialnum = Int.(base.trialnum),
        rffsp_id = Int.(base.rffsp_id),
        fair_parameter_set_id = Int.(base.fair_parameter_set_id),
        geography = fill(TARGET_GEOGRAPHY, n),
        metric = fill(metric, n),

        value_usd2005_per_t_ch4 = values_2005,
        value_usd2026_per_t_ch4 = values_2026,

        original_unit = fill(ORIGINAL_UNIT, n),
        current_unit = fill(CURRENT_UNIT, n),

        source = fill(source, n),

        cpi_u_2005 = fill(CPI_2005_ANNUAL_AVERAGE, n),
        cpi_u_2026 = fill(CPI_2026_CURRENT, n),
        cpi_uprating_factor = fill(CPI_UPRATING_FACTOR, n),

        price_basis = fill(PRICE_BASIS, n),
        cpi_source = fill(CPI_SOURCE, n),
    )
end


function summarize_factors(df::DataFrame)

    group_cols = [
        :gas,
        :pulse_year,
        :geography,
        :metric,
        :source,
    ]

    result = DataFrame(
        gas = String[],
        pulse_year = Int[],
        geography = String[],
        metric = String[],
        statistic = String[],

        value_usd2005_per_t_ch4 = Float64[],
        value_usd2026_per_t_ch4 = Float64[],

        original_unit = String[],
        current_unit = String[],

        source = String[],
        n_trials = Int[],

        cpi_u_2005 = Float64[],
        cpi_u_2026 = Float64[],
        cpi_uprating_factor = Float64[],

        price_basis = String[],
        cpi_source = String[],
    )

    for group in groupby(df, group_cols)

        values_2005 =
            Float64.(group.value_usd2005_per_t_ch4)

        isempty(values_2005) && continue

        all(isfinite, values_2005) || error(
            "Non-finite values found for " *
            "$(group.metric[1]), $(group.pulse_year[1])."
        )

        stats = [
            (
                "mean",
                mean(values_2005),
            ),
            (
                "median",
                median(values_2005),
            ),
            (
                "p05",
                quantile(values_2005, 0.05),
            ),
            (
                "p95",
                quantile(values_2005, 0.95),
            ),
        ]

        for (statistic, value_2005) in stats

            value_2026 =
                value_2005 * CPI_UPRATING_FACTOR

            push!(
                result,
                (
                    gas = String(group.gas[1]),
                    pulse_year = Int(group.pulse_year[1]),
                    geography = String(group.geography[1]),
                    metric = String(group.metric[1]),
                    statistic = statistic,

                    value_usd2005_per_t_ch4 =
                        Float64(value_2005),

                    value_usd2026_per_t_ch4 =
                        Float64(value_2026),

                    original_unit = ORIGINAL_UNIT,
                    current_unit = CURRENT_UNIT,

                    source = String(group.source[1]),

                    n_trials = length(values_2005),

                    cpi_u_2005 =
                        CPI_2005_ANNUAL_AVERAGE,

                    cpi_u_2026 =
                        CPI_2026_CURRENT,

                    cpi_uprating_factor =
                        CPI_UPRATING_FACTOR,

                    price_basis =
                        PRICE_BASIS,

                    cpi_source =
                        CPI_SOURCE,
                ),
            )
        end
    end

    sort!(
        result,
        [
            :pulse_year,
            :metric,
            :statistic,
        ],
    )

    return result
end


# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------

println(
    "Loading existing trial-level monetary impact libraries..."
)

isfile(MONETARY_PATH) || error(
    "Monetary impact library not found: $MONETARY_PATH"
)

isfile(OZONE_PATH) || error(
    "Ozone monetary impact library not found: $OZONE_PATH"
)

monetary_all =
    DataFrame(load(MONETARY_PATH))

ozone_all =
    DataFrame(load(OZONE_PATH))


# ---------------------------------------------------------------------------
# Validate schemas
# ---------------------------------------------------------------------------

require_columns(
    monetary_all,
    [
        :pulse_year,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :geography,
        :metric,
        :value,
        :unit,
    ],
    "Monetary impact library",
)

require_columns(
    ozone_all,
    [
        :pulse_year,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :geography,
        :ozone_mortality_monetised_usd2005_per_t_ch4,
    ],
    "Ozone monetary impact library",
)


# ---------------------------------------------------------------------------
# Restrict to global damages
# ---------------------------------------------------------------------------

monetary = monetary_all[
    String.(monetary_all.geography) .==
    TARGET_GEOGRAPHY,
    :,
]

ozone = ozone_all[
    String.(ozone_all.geography) .==
    TARGET_GEOGRAPHY,
    :,
]

nrow(monetary) > 0 || error(
    "No global rows found in monetary impact library."
)

nrow(ozone) > 0 || error(
    "No global rows found in ozone monetary impact library."
)

println()
println(
    "Filtering export to geography = '$TARGET_GEOGRAPHY' only."
)

println(
    "Global GIVE rows: ",
    nrow(monetary),
)

println(
    "Global ozone rows: ",
    nrow(ozone),
)


# ---------------------------------------------------------------------------
# Validate monetary units
# ---------------------------------------------------------------------------

monetary_units =
    unique(String.(monetary.unit))

length(monetary_units) == 1 || error(
    "Expected one monetary unit in global GIVE library, found: " *
    join(monetary_units, ", ")
)

give_monetary_unit =
    monetary_units[1]

give_monetary_unit == ORIGINAL_UNIT || error(
    "Unexpected GIVE monetary unit: $give_monetary_unit"
)


# ---------------------------------------------------------------------------
# Validate values
# ---------------------------------------------------------------------------

all(
    isfinite,
    Float64.(monetary.value),
) || error(
    "Global monetary impact library contains non-finite values."
)

all(
    isfinite,
    Float64.(
        ozone.ozone_mortality_monetised_usd2005_per_t_ch4
    ),
) || error(
    "Global ozone monetary impact library contains non-finite values."
)


# ---------------------------------------------------------------------------
# Inspect existing GIVE monetary metrics
# ---------------------------------------------------------------------------

monetary_metrics =
    sort(unique(String.(monetary.metric)))

println()
println("Global GIVE monetary metrics found:")

for metric in monetary_metrics
    println("  ", metric)
end

GIVE_HEADLINE_TOTAL_METRIC in monetary_metrics || error(
    "Required headline GIVE metric " *
    "'$GIVE_HEADLINE_TOTAL_METRIC' was not found."
)

println()
println(
    "Headline GIVE climate-total metric: ",
    GIVE_HEADLINE_TOTAL_METRIC,
)

if "total_monetised_excl_agriculture" in monetary_metrics

    println(
        "Alternative sensitivity metric retained separately: ",
        "total_monetised_excl_agriculture",
    )
end


# ---------------------------------------------------------------------------
# Extract headline GIVE climate total
# ---------------------------------------------------------------------------

headline_mask =
    String.(monetary.metric) .==
    GIVE_HEADLINE_TOTAL_METRIC

give_climate_total = select(
    monetary[headline_mask, :],
    vcat(
        KEY_COLS,
        [:value],
    ),
)

rename!(
    give_climate_total,
    :value => :give_climate_total_value,
)

assert_unique(
    give_climate_total,
    KEY_COLS,
    "Global headline GIVE total metric",
)

nrow(give_climate_total) > 0 || error(
    "No global rows found for headline GIVE metric " *
    "'$GIVE_HEADLINE_TOTAL_METRIC'."
)


# ---------------------------------------------------------------------------
# Validate ozone alignment
# ---------------------------------------------------------------------------

assert_unique(
    ozone,
    KEY_COLS,
    "Global ozone monetary impact library",
)

unmatched_ozone = antijoin(
    select(
        ozone,
        KEY_COLS,
    ),
    select(
        give_climate_total,
        KEY_COLS,
    ),
    on = KEY_COLS,
)

isempty(unmatched_ozone) || error(
    "Some global ozone rows have no matching GIVE monetary trial rows. " *
    "Unmatched rows: $(nrow(unmatched_ozone))"
)

unmatched_give = antijoin(
    select(
        give_climate_total,
        KEY_COLS,
    ),
    select(
        ozone,
        KEY_COLS,
    ),
    on = KEY_COLS,
)

isempty(unmatched_give) || error(
    "Some global GIVE total rows have no matching ozone monetary trial rows. " *
    "Unmatched rows: $(nrow(unmatched_give))"
)

combined = innerjoin(
    give_climate_total,
    select(
        ozone,
        vcat(
            KEY_COLS,
            [
                :ozone_mortality_monetised_usd2005_per_t_ch4,
            ],
        ),
    ),
    on = KEY_COLS,
)

nrow(combined) > 0 || error(
    "No matching global GIVE and ozone monetary trial rows were found."
)

nrow(combined) == nrow(give_climate_total) || error(
    "Joined row count differs from global GIVE headline total row count."
)

nrow(combined) == nrow(ozone) || error(
    "Joined row count differs from global ozone monetary row count."
)

println()
println(
    "Matched global GIVE × ozone trial rows: ",
    nrow(combined),
)


# ---------------------------------------------------------------------------
# Existing global GIVE component and sensitivity rows
# ---------------------------------------------------------------------------

give_component_rows = make_factor_rows(
    monetary,
    "",
    monetary.value,
    "GIVE",
)

give_component_rows.metric =
    String.(monetary.metric)


# ---------------------------------------------------------------------------
# Normalized GIVE headline total
# ---------------------------------------------------------------------------

give_total_rows = make_factor_rows(
    give_climate_total,
    "give_climate_total_monetised",
    give_climate_total.give_climate_total_value,
    "GIVE",
)


# ---------------------------------------------------------------------------
# Global methane-induced ozone mortality monetary factor
# ---------------------------------------------------------------------------

ozone_monetised_rows = make_factor_rows(
    combined,
    "ozone_mortality_monetised",
    combined.ozone_mortality_monetised_usd2005_per_t_ch4,
    "McDuffie ozone + GIVE valuation",
)


# ---------------------------------------------------------------------------
# Global extended total monetary damage factor
#
# Headline global GIVE climate damages
# +
# global methane-induced ozone mortality damages
# ---------------------------------------------------------------------------

extended_total_values =
    combined.give_climate_total_value .+
    combined.ozone_mortality_monetised_usd2005_per_t_ch4

extended_total_rows = make_factor_rows(
    combined,
    "extended_total_monetised",
    extended_total_values,
    "GIVE + McDuffie ozone",
)


# ---------------------------------------------------------------------------
# Combine trial-level monetary factors
# ---------------------------------------------------------------------------

factor_trials = vcat(
    give_component_rows,
    give_total_rows,
    ozone_monetised_rows,
    extended_total_rows,
    cols = :setequal,
)

sort!(
    factor_trials,
    [
        :pulse_year,
        :metric,
        :trialnum,
    ],
)


# ---------------------------------------------------------------------------
# QA
# ---------------------------------------------------------------------------

all(
    String.(factor_trials.geography) .==
    TARGET_GEOGRAPHY
) || error(
    "Non-global rows detected in global reduced-form export."
)

all(
    isfinite,
    factor_trials.value_usd2005_per_t_ch4,
) || error(
    "Non-finite USD2005 values detected."
)

all(
    isfinite,
    factor_trials.value_usd2026_per_t_ch4,
) || error(
    "Non-finite USD2026 values detected."
)

converted_check =
    factor_trials.value_usd2005_per_t_ch4 .*
    CPI_UPRATING_FACTOR

maximum(
    abs.(
        converted_check .-
        factor_trials.value_usd2026_per_t_ch4
    )
) < 1e-8 || error(
    "USD2026 conversion QA failed."
)

duplicate_check = combine(
    groupby(
        factor_trials,
        [
            :gas,
            :pulse_year,
            :trialnum,
            :rffsp_id,
            :fair_parameter_set_id,
            :geography,
            :metric,
            :source,
        ],
    ),
    nrow => :n,
)

duplicate_rows = duplicate_check[
    duplicate_check.n .> 1,
    :,
]

isempty(duplicate_rows) || error(
    "Duplicate global monetary factor rows detected after export construction."
)


# ---------------------------------------------------------------------------
# Summary statistics
# ---------------------------------------------------------------------------

factor_summary =
    summarize_factors(factor_trials)


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

save(
    TRIAL_OUTPUT_PATH,
    factor_trials,
)

save(
    SUMMARY_OUTPUT_PATH,
    factor_summary,
)


# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------

println()
println(
    "Global reduced-form CH4 monetary damage factor export complete."
)

println()
println("Price conversion:")
println(
    "  2005 CPI-U annual average: ",
    CPI_2005_ANNUAL_AVERAGE,
)

println(
    "  August 2026 CPI-U:         ",
    CPI_2026_CURRENT,
)

println(
    "  Uprating factor:           ",
    round(
        CPI_UPRATING_FACTOR,
        digits = 6,
    ),
)

println()
println("Trial-level output:")
println(
    "  ",
    TRIAL_OUTPUT_PATH,
)

println(
    "  rows: ",
    nrow(factor_trials),
)

println()
println("Summary output:")
println(
    "  ",
    SUMMARY_OUTPUT_PATH,
)

println(
    "  rows: ",
    nrow(factor_summary),
)

println()
println(
    "Pulse years: ",
    join(
        sort(unique(factor_trials.pulse_year)),
        ", ",
    ),
)

println(
    "Geography: ",
    TARGET_GEOGRAPHY,
)

println()
println("Headline GLLEX metric:")
println(
    "  extended_total_monetised"
)

println()
println("Construction:")
println(
    "  global total_monetised + global ozone_mortality_monetised"
)

println()
println(
    "Interpretation: expected discounted global societal damage ",
    "per tonne CH4 emitted."
)

println()
println(
    "Current-dollar output unit: ",
    CURRENT_UNIT,
)

println(
    "Price basis: ",
    PRICE_BASIS,
)

println()
println(
    "Alternative GIVE total_monetised_excl_agriculture is retained ",
    "as a sensitivity metric but is not used in the headline total."
)