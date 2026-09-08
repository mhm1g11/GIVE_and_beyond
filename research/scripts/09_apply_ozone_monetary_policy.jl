using FileIO
using CSVFiles
using DataFrames

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)

# =====================================================================
# Paths
# =====================================================================

const POLICY_INPUT = joinpath(
    INPUT_DIR,
    "mock_methane_abatement.csv"
)

const OZONE_MONETARY_LIBRARY = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_impact_library_give_first.csv"
)

const EXISTING_MONETARY_SUMMARY = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_summary.csv"
)

const OZONE_BY_YEAR_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_ozone_monetary_by_abatement_year.csv"
)

const OZONE_SUMMARY_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_ozone_monetary_summary.csv"
)

const EXPANDED_MEAN_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_expanded_mean.csv"
)

println("APPLYING GIVE-FIRST OZONE MONETARY POLICY BENEFITS")
println("===================================================")
println()

# =====================================================================
# Robust CSV helpers
# =====================================================================

function as_int(x)

    if x isa Integer
        return Int(x)
    end

    return parse(
        Int,
        strip(string(x))
    )
end


function as_float(x)

    if x isa Real
        return Float64(x)
    end

    return parse(
        Float64,
        strip(string(x))
    )
end

# =====================================================================
# Geography helper
# =====================================================================

function benefit_geographies(scope)

    scope_string =
        string(scope)

    if scope_string == "EU27"

        return [
            "globe",
            "EU27"
        ]

    elseif scope_string == "DEU"

        return [
            "globe",
            "DEU"
        ]

    else

        error(
            "Unknown abatement_scope: $scope_string."
        )
    end
end

# =====================================================================
# Load inputs
# =====================================================================

abatement =
    DataFrame(
        load(
            POLICY_INPUT
        )
    )

ozone_library =
    DataFrame(
        load(
            OZONE_MONETARY_LIBRARY
        )
    )

existing_summary =
    DataFrame(
        load(
            EXISTING_MONETARY_SUMMARY
        )
    )

# Normalize important fields.
abatement.year = [
    as_int(x)
    for x in abatement.year
]

abatement.avoided_ch4_t = [
    as_float(x)
    for x in abatement.avoided_ch4_t
]

ozone_library.pulse_year = [
    as_int(x)
    for x in ozone_library.pulse_year
]

ozone_library.ozone_mortality_monetised_usd2005_per_t_ch4 = [
    as_float(x)
    for x in
    ozone_library.ozone_mortality_monetised_usd2005_per_t_ch4
]

# =====================================================================
# 1. Policy ozone monetary benefits by abatement year
# =====================================================================

ozone_by_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    avoided_ch4_t = Float64[],
    ozone_value_usd2005_per_t_ch4 = Float64[],
    ozone_mortality_benefit_usd2005 = Float64[]
)

for policy_row in eachrow(abatement)

    scenario_id =
        string(
            policy_row.scenario_id
        )

    scope =
        string(
            policy_row.abatement_scope
        )

    year =
        as_int(
            policy_row.year
        )

    avoided_ch4_t =
        as_float(
            policy_row.avoided_ch4_t
        )

    for geography in benefit_geographies(scope)

        factor = filter(
            row ->
                as_int(row.pulse_year) == year &&
                string(row.geography) == geography,
            ozone_library
        )

        nrow(factor) == 1 ||
            error(
                "Expected one ozone monetary factor for " *
                "$year / $geography, found $(nrow(factor))."
            )

        value_per_t =
            as_float(
                factor.ozone_mortality_monetised_usd2005_per_t_ch4[1]
            )

        benefit =
            avoided_ch4_t *
            value_per_t

        push!(
            ozone_by_year,
            (
                scenario_id,
                scope,
                year,
                geography,
                avoided_ch4_t,
                value_per_t,
                benefit
            )
        )
    end
end

sort!(
    ozone_by_year,
    [
        :scenario_id,
        :benefit_geography,
        :abatement_year
    ]
)

# =====================================================================
# 2. Sum ozone monetary benefit across policy years
# =====================================================================

ozone_summary = combine(
    groupby(
        ozone_by_year,
        [
            :scenario_id,
            :benefit_geography
        ]
    ),
    :ozone_mortality_benefit_usd2005 =>
        sum =>
        :ozone_mortality_monetised_usd2005
)

sort!(
    ozone_summary,
    [
        :scenario_id,
        :benefit_geography
    ]
)

# =====================================================================
# 3. Build expanded monetary MEAN result
#
# IMPORTANT:
#
# Existing GIVE monetary results are currently 5-trial means.
#
# Ozone is deterministic.
#
# Therefore this output is explicitly a MEAN + deterministic ozone
# calculation.
#
# We do NOT construct p2.5 / p97.5 uncertainty intervals here.
# =====================================================================

expanded = DataFrame(
    scenario_id = String[],
    benefit_geography = String[],
    base_give_metric = String[],
    base_give_mean_usd2005 = Float64[],
    ozone_mortality_monetised_usd2005 = Float64[],
    expanded_mean_usd2005 = Float64[],
    ozone_share_of_expanded_mean = Float64[]
)

for ozone_row in eachrow(ozone_summary)

    scenario_id =
        string(
            ozone_row.scenario_id
        )

    geography =
        string(
            ozone_row.benefit_geography
        )

    ozone_value =
        as_float(
            ozone_row.ozone_mortality_monetised_usd2005
        )

    # -------------------------------------------------------------
    # Select the appropriate existing GIVE total.
    #
    # Global includes:
    #   agriculture + energy + SLR + temperature mortality
    #
    # EU27 / Germany exclude agriculture.
    # -------------------------------------------------------------

    base_metric =
        geography == "globe" ?
            "total_monetised" :
            "total_monetised_excl_agriculture"

    base_row = filter(
        row ->
            string(row.scenario_id) == scenario_id &&
            string(row.benefit_geography) == geography &&
            string(row.metric) == base_metric,
        existing_summary
    )

    nrow(base_row) == 1 ||
        error(
            "Expected one existing GIVE total for " *
            "$scenario_id / $geography / $base_metric, " *
            "found $(nrow(base_row))."
        )

    base_mean =
        as_float(
            base_row.mean_usd2005[1]
        )

    expanded_mean =
        base_mean +
        ozone_value

    ozone_share =
        expanded_mean == 0.0 ?
            0.0 :
            ozone_value /
            expanded_mean

    push!(
        expanded,
        (
            scenario_id,
            geography,
            base_metric,
            base_mean,
            ozone_value,
            expanded_mean,
            ozone_share
        )
    )
end

sort!(
    expanded,
    [
        :scenario_id,
        :benefit_geography
    ]
)

# =====================================================================
# Save
# =====================================================================

save(
    OZONE_BY_YEAR_OUTPUT,
    ozone_by_year
)

save(
    OZONE_SUMMARY_OUTPUT,
    ozone_summary
)

save(
    EXPANDED_MEAN_OUTPUT,
    expanded
)

# =====================================================================
# Console output
# =====================================================================

println("POLICY OZONE MONETARY RESULTS")
println("=============================")
println()

scenario_ids =
    unique(
        ozone_summary.scenario_id
    )

for scenario_id in scenario_ids

    println(
        scenario_id
    )

    println(
        repeat(
            "-",
            length(scenario_id)
        )
    )

    rows = filter(
        row ->
            row.scenario_id == scenario_id,
        expanded
    )

    for row in eachrow(rows)

        println()

        println(
            "  ",
            row.benefit_geography
        )

        println(
            "    Existing GIVE mean        : ",
            round(
                row.base_give_mean_usd2005 / 1e6,
                digits = 3
            ),
            " million USD2005"
        )

        println(
            "    Ozone respiratory         : ",
            round(
                row.ozone_mortality_monetised_usd2005 / 1e6,
                digits = 3
            ),
            " million USD2005"
        )

        println(
            "    Expanded mean             : ",
            round(
                row.expanded_mean_usd2005 / 1e6,
                digits = 3
            ),
            " million USD2005"
        )

        println(
            "    Ozone share               : ",
            round(
                100 *
                row.ozone_share_of_expanded_mean,
                digits = 1
            ),
            "%"
        )
    end

    println()
end

println()
println("Saved:")
println("  ", OZONE_BY_YEAR_OUTPUT)
println("  ", OZONE_SUMMARY_OUTPUT)
println("  ", EXPANDED_MEAN_OUTPUT)

println()
println("IMPORTANT:")
println(
    "The ozone mortality valuation is deterministic."
)

println(
    "The existing GIVE totals are 5-trial Monte Carlo means."
)

println(
    "The expanded mean is therefore suitable as a current proof-of-concept " *
    "central estimate, but it does not yet have a fully aligned uncertainty interval."
)

println(
    "The next step is to make ozone valuation use the same Monte Carlo " *
    "socioeconomic and valuation draws as the existing GIVE monetary library."
)