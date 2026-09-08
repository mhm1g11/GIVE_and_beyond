using FileIO
using CSVFiles
using DataFrames
using Statistics

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)

# =====================================================================
# Input paths
# =====================================================================

const POLICY_INPUT = joinpath(
    INPUT_DIR,
    "mock_methane_abatement.csv"
)

const MONETARY_TRIAL_LIBRARY = joinpath(
    OUTPUT_DIR,
    "monetary_impact_library_trials.csv"
)

const TEMPERATURE_CUMULATIVE_LIBRARY = joinpath(
    OUTPUT_DIR,
    "mortality_cumulative_library.csv"
)

const TEMPERATURE_ANNUAL_LIBRARY = joinpath(
    OUTPUT_DIR,
    "mortality_response_library.csv"
)

# Preferred GIVE-first ozone mortality libraries:
#
#   GIVE/FaIR atmospheric methane
#   + GIVE population
#   + GIVE all-cause mortality trajectory
#   + McDuffie ozone-health calibration only
#
const OZONE_CUMULATIVE_LIBRARY = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_cumulative_library_give_first.csv"
)

const OZONE_ANNUAL_LIBRARY = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_response_library_give_first.csv"
)

# =====================================================================
# Output paths
# =====================================================================

mkpath(POLICY_RESULT_DIR)

const MONETARY_BY_YEAR_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_by_abatement_year_trials.csv"
)

const MONETARY_SUMMARY_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_summary.csv"
)

const MORTALITY_BY_YEAR_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_by_abatement_year.csv"
)

const MORTALITY_SUMMARY_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_summary.csv"
)

const MORTALITY_IMPACT_YEAR_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_by_impact_year.csv"
)

# =====================================================================
# Helpers
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
            "Unknown abatement_scope: $scope_string. " *
            "Expected EU27 or DEU."
        )
    end
end


function find_single_row(
    df::DataFrame;
    pulse_year::Int,
    geography::String
)

    subset = filter(
        row ->
            Int(row.pulse_year) == pulse_year &&
            string(row.geography) == geography,
        df
    )

    nrow(subset) == 1 ||
        error(
            "Expected exactly one row for pulse_year=$pulse_year, " *
            "geography=$geography, but found $(nrow(subset))."
        )

    return subset[1, :]
end


function add_combined_mortality_by_abatement_year(
    pathway_rows::DataFrame
)

    combined = combine(
        groupby(
            pathway_rows,
            [
                :scenario_id,
                :abatement_scope,
                :abatement_year,
                :benefit_geography,
                :avoided_ch4_t
            ]
        ),
        :deaths_avoided =>
            sum =>
            :deaths_avoided
    )

    combined.mortality_pathway .=
        "combined_quantified"

    return vcat(
        pathway_rows,
        select(
            combined,
            names(pathway_rows)
        )
    )
end


function add_combined_mortality_by_impact_year(
    pathway_rows::DataFrame
)

    combined = combine(
        groupby(
            pathway_rows,
            [
                :scenario_id,
                :benefit_geography,
                :impact_year
            ]
        ),
        :deaths_avoided =>
            sum =>
            :deaths_avoided
    )

    combined.mortality_pathway .=
        "combined_quantified"

    return vcat(
        pathway_rows,
        select(
            combined,
            names(pathway_rows)
        )
    )
end

# =====================================================================
# Load inputs
# =====================================================================

println("APPLYING POLICY SCENARIO")
println("========================")
println()

abatement =
    DataFrame(
        load(POLICY_INPUT)
    )

monetary_trials =
    DataFrame(
        load(MONETARY_TRIAL_LIBRARY)
    )

temperature_cumulative =
    DataFrame(
        load(TEMPERATURE_CUMULATIVE_LIBRARY)
    )

temperature_annual =
    DataFrame(
        load(TEMPERATURE_ANNUAL_LIBRARY)
    )

ozone_cumulative =
    DataFrame(
        load(OZONE_CUMULATIVE_LIBRARY)
    )

ozone_annual =
    DataFrame(
        load(OZONE_ANNUAL_LIBRARY)
    )

# =====================================================================
# 1. Monetary benefits
#
# These are still GIVE monetary outputs from the original GIVE sectors.
#
# Ozone mortality is NOT monetised yet.
#
# Because the Monte Carlo trials are aligned across pulse years,
# policy benefits can be summed across abatement years within the same
# trial before calculating summary statistics across trials.
# =====================================================================

monetary_by_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    trialnum = Int[],
    metric = String[],
    avoided_ch4_t = Float64[],
    impact_value_per_t_ch4 = Float64[],
    monetised_benefit_usd2005 = Float64[]
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
        Int(
            policy_row.year
        )

    avoided_ch4_t =
        Float64(
            policy_row.avoided_ch4_t
        )

    for geography in benefit_geographies(scope)

        factors = filter(
            row ->
                Int(row.pulse_year) == year &&
                string(row.geography) == geography,
            monetary_trials
        )

        nrow(factors) > 0 ||
            error(
                "No monetary impact factors found for " *
                "$year / $geography."
            )

        for factor in eachrow(factors)

            value_per_t =
                Float64(
                    factor.value
                )

            benefit =
                avoided_ch4_t *
                value_per_t

            push!(
                monetary_by_year,
                (
                    scenario_id,
                    scope,
                    year,
                    geography,
                    Int(factor.trialnum),
                    string(factor.metric),
                    avoided_ch4_t,
                    value_per_t,
                    benefit
                )
            )
        end
    end
end

sort!(
    monetary_by_year,
    [
        :scenario_id,
        :benefit_geography,
        :metric,
        :trialnum,
        :abatement_year
    ]
)

# Sum policy years within each aligned Monte Carlo trial.
monetary_trial_totals = combine(
    groupby(
        monetary_by_year,
        [
            :scenario_id,
            :benefit_geography,
            :trialnum,
            :metric
        ]
    ),
    :monetised_benefit_usd2005 =>
        sum =>
        :monetised_benefit_usd2005
)

# Then summarize across trials.
monetary_summary = combine(
    groupby(
        monetary_trial_totals,
        [
            :scenario_id,
            :benefit_geography,
            :metric
        ]
    ),

    :monetised_benefit_usd2005 =>
        mean =>
        :mean_usd2005,

    :monetised_benefit_usd2005 =>
        median =>
        :median_usd2005,

    :monetised_benefit_usd2005 =>
        (x -> quantile(x, 0.025)) =>
        :p2_5_usd2005,

    :monetised_benefit_usd2005 =>
        (x -> quantile(x, 0.975)) =>
        :p97_5_usd2005,

    nrow =>
        :n_trials
)

sort!(
    monetary_summary,
    [
        :scenario_id,
        :benefit_geography,
        :metric
    ]
)

# =====================================================================
# 2. Physical mortality by abatement year
#
# Two quantified pathways:
#
# temperature
#   GIVE temperature-related mortality
#
# ozone_respiratory
#   GIVE/FaIR methane
#   + GIVE population
#   + GIVE all-cause mortality
#   + McDuffie ozone-health calibration
#
# combined_quantified
#   simple sum of the two physical mortality pathways
# =====================================================================

mortality_by_abatement_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    avoided_ch4_t = Float64[],
    mortality_pathway = String[],
    deaths_avoided = Float64[]
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
        Int(
            policy_row.year
        )

    avoided_ch4_t =
        Float64(
            policy_row.avoided_ch4_t
        )

    for geography in benefit_geographies(scope)

        # ---------------------------------------------------------
        # GIVE temperature mortality
        # ---------------------------------------------------------

        temperature_factor =
            find_single_row(
                temperature_cumulative;
                pulse_year = year,
                geography = geography
            )

        temperature_deaths =
            avoided_ch4_t *
            Float64(
                temperature_factor.cumulative_deaths_per_t_ch4
            )

        push!(
            mortality_by_abatement_year,
            (
                scenario_id,
                scope,
                year,
                geography,
                avoided_ch4_t,
                "temperature",
                temperature_deaths
            )
        )

        # ---------------------------------------------------------
        # GIVE-first ozone respiratory mortality
        # ---------------------------------------------------------

        ozone_factor =
            find_single_row(
                ozone_cumulative;
                pulse_year = year,
                geography = geography
            )

        ozone_deaths =
            avoided_ch4_t *
            Float64(
                ozone_factor.cumulative_deaths_per_t_ch4
            )

        push!(
            mortality_by_abatement_year,
            (
                scenario_id,
                scope,
                year,
                geography,
                avoided_ch4_t,
                "ozone_respiratory",
                ozone_deaths
            )
        )
    end
end

# Add the combined physical mortality pathway.
mortality_by_abatement_year =
    add_combined_mortality_by_abatement_year(
        mortality_by_abatement_year
    )

sort!(
    mortality_by_abatement_year,
    [
        :scenario_id,
        :benefit_geography,
        :mortality_pathway,
        :abatement_year
    ]
)

# =====================================================================
# 3. Physical mortality summary
# =====================================================================

mortality_summary = combine(
    groupby(
        mortality_by_abatement_year,
        [
            :scenario_id,
            :benefit_geography,
            :mortality_pathway
        ]
    ),
    :deaths_avoided =>
        sum =>
        :deaths_avoided
)

sort!(
    mortality_summary,
    [
        :scenario_id,
        :benefit_geography,
        :mortality_pathway
    ]
)

# =====================================================================
# 4. Physical mortality by actual impact year
#
# Dynamic convolution:
#
# every annual methane abatement pulse
#   ×
# every subsequent annual mortality response
#
# Then overlapping pulse responses are summed by impact year.
# =====================================================================

mortality_impact_pathways = DataFrame(
    scenario_id = String[],
    benefit_geography = String[],
    impact_year = Int[],
    mortality_pathway = String[],
    deaths_avoided = Float64[]
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

    pulse_year =
        Int(
            policy_row.year
        )

    avoided_ch4_t =
        Float64(
            policy_row.avoided_ch4_t
        )

    for geography in benefit_geographies(scope)

        # ---------------------------------------------------------
        # GIVE temperature mortality annual response
        # ---------------------------------------------------------

        temperature_response = filter(
            row ->
                Int(row.pulse_year) == pulse_year &&
                string(row.geography) == geography,
            temperature_annual
        )

        nrow(temperature_response) > 0 ||
            error(
                "No temperature mortality response found for " *
                "$pulse_year / $geography."
            )

        for response_row in eachrow(
            temperature_response
        )

            deaths =
                avoided_ch4_t *
                Float64(
                    response_row.deaths_per_t_ch4
                )

            push!(
                mortality_impact_pathways,
                (
                    scenario_id,
                    geography,
                    Int(response_row.impact_year),
                    "temperature",
                    deaths
                )
            )
        end

        # ---------------------------------------------------------
        # GIVE-first ozone respiratory annual response
        # ---------------------------------------------------------

        ozone_response = filter(
            row ->
                Int(row.pulse_year) == pulse_year &&
                string(row.geography) == geography,
            ozone_annual
        )

        nrow(ozone_response) > 0 ||
            error(
                "No ozone mortality response found for " *
                "$pulse_year / $geography."
            )

        for response_row in eachrow(
            ozone_response
        )

            deaths =
                avoided_ch4_t *
                Float64(
                    response_row.deaths_per_t_ch4
                )

            push!(
                mortality_impact_pathways,
                (
                    scenario_id,
                    geography,
                    Int(response_row.impact_year),
                    "ozone_respiratory",
                    deaths
                )
            )
        end
    end
end

# Sum overlapping annual methane pulses within each mortality pathway.
mortality_by_impact_year = combine(
    groupby(
        mortality_impact_pathways,
        [
            :scenario_id,
            :benefit_geography,
            :impact_year,
            :mortality_pathway
        ]
    ),
    :deaths_avoided =>
        sum =>
        :deaths_avoided
)

# Add combined quantified mortality by impact year.
mortality_by_impact_year =
    add_combined_mortality_by_impact_year(
        mortality_by_impact_year
    )

sort!(
    mortality_by_impact_year,
    [
        :scenario_id,
        :benefit_geography,
        :mortality_pathway,
        :impact_year
    ]
)

# =====================================================================
# Save outputs
# =====================================================================

save(
    MONETARY_BY_YEAR_OUTPUT,
    monetary_by_year
)

save(
    MONETARY_SUMMARY_OUTPUT,
    monetary_summary
)

save(
    MORTALITY_BY_YEAR_OUTPUT,
    mortality_by_abatement_year
)

save(
    MORTALITY_SUMMARY_OUTPUT,
    mortality_summary
)

save(
    MORTALITY_IMPACT_YEAR_OUTPUT,
    mortality_by_impact_year
)

# =====================================================================
# Console summary
# =====================================================================

println()
println("POLICY PROOF OF CONCEPT COMPLETE")
println("================================")
println()

scenario_ids =
    unique(
        string.(
            abatement.scenario_id
        )
    )

for scenario_id in scenario_ids

    println()
    println(scenario_id)
    println(
        repeat(
            "-",
            length(scenario_id)
        )
    )
    println()

    scenario_policy = filter(
        row ->
            string(row.scenario_id) ==
            scenario_id,
        abatement
    )

    total_abatement_mt =
        sum(
            Float64.(
                scenario_policy.avoided_ch4_t
            )
        ) / 1e6

    scenario_mortality = filter(
        row ->
            string(row.scenario_id) ==
            scenario_id,
        mortality_summary
    )

    geographies =
        unique(
            string.(
                scenario_mortality.benefit_geography
            )
        )

    println(
        "Physical mortality, ",
        round(
            total_abatement_mt,
            digits = 3
        ),
        " Mt CH4 avoided:"
    )

    for geography in geographies

        println()
        println(
            "  ",
            geography
        )

        geo_rows = filter(
            row ->
                string(row.benefit_geography) ==
                geography,
            scenario_mortality
        )

        for pathway in [
            "temperature",
            "ozone_respiratory",
            "combined_quantified"
        ]

            pathway_row = filter(
                row ->
                    string(row.mortality_pathway) ==
                    pathway,
                geo_rows
            )

            nrow(pathway_row) == 1 ||
                continue

            label =
                pathway == "temperature" ?
                    "Temperature-related" :
                pathway == "ozone_respiratory" ?
                    "Ozone respiratory" :
                    "Combined quantified"

            println(
                "    ",
                rpad(
                    label,
                    24
                ),
                ": ",
                pathway_row.deaths_avoided[1],
                " deaths avoided through ",
                IMPACT_HORIZON
            )
        end
    end

    println()
    println(
        "Monetary benefits, ",
        maximum(
            monetary_summary.n_trials
        ),
        "-trial test means:"
    )

    scenario_money = filter(
        row ->
            string(row.scenario_id) ==
            scenario_id,
        monetary_summary
    )

    money_geographies =
        unique(
            string.(
                scenario_money.benefit_geography
            )
        )

    for geography in money_geographies

        println()
        println(
            "  ",
            geography
        )

        geo_money = filter(
            row ->
                string(row.benefit_geography) ==
                geography,
            scenario_money
        )

        sort!(
            geo_money,
            :metric
        )

        for row in eachrow(
            geo_money
        )

            println(
                "    ",
                rpad(
                    string(row.metric),
                    40
                ),
                ": ",
                row.mean_usd2005 / 1e6,
                " million USD2005"
            )
        end
    end
end

println()
println()
println("Saved policy outputs:")

println(
    "  ",
    MONETARY_BY_YEAR_OUTPUT
)

println(
    "  ",
    MONETARY_SUMMARY_OUTPUT
)

println(
    "  ",
    MORTALITY_BY_YEAR_OUTPUT
)

println(
    "  ",
    MORTALITY_SUMMARY_OUTPUT
)

println(
    "  ",
    MORTALITY_IMPACT_YEAR_OUTPUT
)

println()
println("IMPORTANT:")

println(
    "Physical ozone mortality now uses the preferred GIVE-first " *
    "implementation: GIVE/FaIR methane, GIVE population, GIVE " *
    "all-cause mortality trajectories, and only the ozone-health " *
    "calibration from McDuffie."
)

println(
    "Monetary results still contain GIVE temperature mortality only. " *
    "Ozone respiratory mortality has not yet been monetised."
)

println(
    "Physical combined mortality equals GIVE temperature mortality " *
    "plus GIVE-first ozone respiratory mortality."
)

println(
    "EU27 and German GIVE monetary totals exclude agriculture."
)

println(
    "Monetary results use only the current 5 aligned Monte Carlo trials."
)