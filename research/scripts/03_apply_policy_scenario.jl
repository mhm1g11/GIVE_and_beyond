using FileIO
using CSVFiles
using DataFrames
using Statistics

include(joinpath(@__DIR__, "config.jl"))

# ================================================================
# Input paths
# ================================================================

const ABATEMENT_PATH = joinpath(
    INPUT_DIR,
    "mock_methane_abatement.csv"
)

const MONETARY_PATH = joinpath(
    OUTPUT_DIR,
    "monetary_impact_library_trials.csv"
)

const MORTALITY_CUMULATIVE_PATH = joinpath(
    OUTPUT_DIR,
    "mortality_cumulative_library.csv"
)

const MORTALITY_RESPONSE_PATH = joinpath(
    OUTPUT_DIR,
    "mortality_response_library.csv"
)

# ================================================================
# Output paths
# ================================================================

const MONETARY_BY_YEAR_PATH = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_by_abatement_year_trials.csv"
)

const MONETARY_SUMMARY_PATH = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_summary.csv"
)

const MORTALITY_BY_ABATEMENT_YEAR_PATH = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_by_abatement_year.csv"
)

const MORTALITY_SUMMARY_PATH = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_summary.csv"
)

const MORTALITY_BY_IMPACT_YEAR_PATH = joinpath(
    POLICY_RESULT_DIR,
    "policy_mortality_by_impact_year.csv"
)

mkpath(POLICY_RESULT_DIR)

# ================================================================
# Load inputs
# ================================================================

abatement = DataFrame(load(ABATEMENT_PATH))
monetary = DataFrame(load(MONETARY_PATH))
mortality_cumulative = DataFrame(load(MORTALITY_CUMULATIVE_PATH))
mortality_response = DataFrame(load(MORTALITY_RESPONSE_PATH))

# ================================================================
# QA checks
# ================================================================

required_abatement_columns = [
    :scenario_id,
    :abatement_scope,
    :year,
    :avoided_ch4_t
]

for col in required_abatement_columns
    col in propertynames(abatement) ||
        error("Missing abatement input column: $col")
end

available_pulse_years =
    sort(unique(monetary.pulse_year))

missing_years =
    setdiff(
        sort(unique(abatement.year)),
        available_pulse_years
    )

isempty(missing_years) ||
    error(
        "Policy years missing from GIVE monetary library: $missing_years"
    )

# ================================================================
# Which benefit geographies belong to each abatement scenario?
#
# EU27 abatement:
#   global benefits + EU27 benefits
#
# Germany-attributable abatement:
#   global benefits + German benefits
#
# Deliberately do NOT calculate EU27 abatement -> Germany benefits
# in the headline policy output.
# ================================================================

function benefit_geographies(
    abatement_scope::String
)

    if abatement_scope == "EU27"

        return [
            "globe",
            "EU27"
        ]

    elseif abatement_scope == GERMANY

        return [
            "globe",
            GERMANY
        ]

    else

        error(
            "Unsupported abatement scope: $abatement_scope"
        )
    end
end

# ================================================================
# 1. MONETARY BENEFITS BY ABATEMENT YEAR AND TRIAL
# ================================================================

monetary_by_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    metric = String[],
    trialnum = Int[],
    avoided_ch4_t = Float64[],
    impact_factor_usd2005_per_t_ch4 = Float64[],
    avoided_benefit_usd2005 = Float64[]
)

for policy_row in eachrow(abatement)

    scenario_id =
        String(policy_row.scenario_id)

    scope =
        String(policy_row.abatement_scope)

    year =
        Int(policy_row.year)

    avoided_ch4_t =
        Float64(policy_row.avoided_ch4_t)

    for geography in benefit_geographies(scope)

        factors = filter(
            row ->
                row.pulse_year == year &&
                row.geography == geography,
            monetary
        )

        nrow(factors) > 0 ||
            error(
                "No monetary factors for year=$year, geography=$geography"
            )

        for factor_row in eachrow(factors)

            avoided_benefit =
                avoided_ch4_t *
                factor_row.value

            push!(
                monetary_by_year,
                (
                    scenario_id,
                    scope,
                    year,
                    geography,
                    String(factor_row.metric),
                    Int(factor_row.trialnum),
                    avoided_ch4_t,
                    Float64(factor_row.value),
                    Float64(avoided_benefit)
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

# ================================================================
# Sum policy years WITHIN each aligned Monte Carlo trial
#
# This is why trial alignment across pulse years mattered.
# ================================================================

monetary_trial_totals = combine(
    groupby(
        monetary_by_year,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :metric,
            :trialnum
        ]
    ),

    :avoided_benefit_usd2005 =>
        sum =>
        :avoided_benefit_usd2005
)

# ================================================================
# Then summarise ACROSS trials
#
# With only 5 trials, mean/median are proof-of-concept only.
# ================================================================

monetary_summary = combine(
    groupby(
        monetary_trial_totals,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :metric
        ]
    ),

    :avoided_benefit_usd2005 =>
        mean =>
        :mean_avoided_benefit_usd2005,

    :avoided_benefit_usd2005 =>
        median =>
        :median_avoided_benefit_usd2005,

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

# ================================================================
# 2. CUMULATIVE PHYSICAL MORTALITY BY ABATEMENT YEAR
#
# Each row asks:
# "How many net temperature-related deaths through 2100 are
# avoided by the methane reduction occurring in this year?"
# ================================================================

mortality_by_abatement_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    avoided_ch4_t = Float64[],
    deaths_per_t_ch4 = Float64[],
    deaths_avoided_through_horizon = Float64[],
    impact_horizon = Int[]
)

for policy_row in eachrow(abatement)

    scenario_id =
        String(policy_row.scenario_id)

    scope =
        String(policy_row.abatement_scope)

    year =
        Int(policy_row.year)

    avoided_ch4_t =
        Float64(policy_row.avoided_ch4_t)

    for geography in benefit_geographies(scope)

        factor = filter(
            row ->
                row.pulse_year == year &&
                row.geography == geography,
            mortality_cumulative
        )

        nrow(factor) == 1 ||
            error(
                "Expected one mortality factor for year=$year, geography=$geography"
            )

        deaths_per_t =
            Float64(
                factor.cumulative_deaths_per_t_ch4[1]
            )

        deaths_avoided =
            avoided_ch4_t *
            deaths_per_t

        push!(
            mortality_by_abatement_year,
            (
                scenario_id,
                scope,
                year,
                geography,
                avoided_ch4_t,
                deaths_per_t,
                deaths_avoided,
                IMPACT_HORIZON
            )
        )
    end
end

sort!(
    mortality_by_abatement_year,
    [
        :scenario_id,
        :benefit_geography,
        :abatement_year
    ]
)

# ================================================================
# Cumulative mortality summary across all policy years
# ================================================================

mortality_summary = combine(
    groupby(
        mortality_by_abatement_year,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :impact_horizon
        ]
    ),

    :avoided_ch4_t =>
        sum =>
        :total_avoided_ch4_t,

    :deaths_avoided_through_horizon =>
        sum =>
        :net_temperature_deaths_avoided
)

sort!(
    mortality_summary,
    [
        :scenario_id,
        :benefit_geography
    ]
)

# ================================================================
# 3. MORTALITY BENEFITS BY CALENDAR / IMPACT YEAR
#
# This performs the dynamic convolution:
#
# deaths avoided in year t =
# sum over all prior methane-abatement years p of
#
# avoided CH4[p] * mortality response[p, t]
#
# ================================================================

mortality_impact_rows = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    impact_year = Int[],
    avoided_ch4_t = Float64[],
    deaths_per_t_ch4 = Float64[],
    deaths_avoided = Float64[]
)

for policy_row in eachrow(abatement)

    scenario_id =
        String(policy_row.scenario_id)

    scope =
        String(policy_row.abatement_scope)

    year =
        Int(policy_row.year)

    avoided_ch4_t =
        Float64(policy_row.avoided_ch4_t)

    for geography in benefit_geographies(scope)

        responses = filter(
            row ->
                row.pulse_year == year &&
                row.geography == geography,
            mortality_response
        )

        nrow(responses) > 0 ||
            error(
                "No mortality response for year=$year, geography=$geography"
            )

        for response_row in eachrow(responses)

            deaths_avoided =
                avoided_ch4_t *
                response_row.deaths_per_t_ch4

            push!(
                mortality_impact_rows,
                (
                    scenario_id,
                    scope,
                    year,
                    geography,
                    Int(response_row.impact_year),
                    avoided_ch4_t,
                    Float64(response_row.deaths_per_t_ch4),
                    Float64(deaths_avoided)
                )
            )
        end
    end
end

# Sum contributions from all abatement years into each future year.
mortality_by_impact_year = combine(
    groupby(
        mortality_impact_rows,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :impact_year
        ]
    ),

    :deaths_avoided =>
        sum =>
        :net_temperature_deaths_avoided
)

sort!(
    mortality_by_impact_year,
    [
        :scenario_id,
        :benefit_geography,
        :impact_year
    ]
)

# ================================================================
# Save outputs
# ================================================================

save(
    MONETARY_BY_YEAR_PATH,
    monetary_by_year
)

save(
    MONETARY_SUMMARY_PATH,
    monetary_summary
)

save(
    MORTALITY_BY_ABATEMENT_YEAR_PATH,
    mortality_by_abatement_year
)

save(
    MORTALITY_SUMMARY_PATH,
    mortality_summary
)

save(
    MORTALITY_BY_IMPACT_YEAR_PATH,
    mortality_by_impact_year
)

# ================================================================
# Print compact result summary
# ================================================================

println()
println("POLICY PROOF OF CONCEPT COMPLETE")
println("================================")
println()

for scenario in unique(abatement.scenario_id)

    scenario_string =
        String(scenario)

    println()
    println(scenario_string)
    println("-" ^ length(scenario_string))

    scenario_mortality = filter(
        row ->
            row.scenario_id == scenario_string,
        mortality_summary
    )

    println()
    println("Physical mortality:")

    for row in eachrow(scenario_mortality)

        println(
            "  ",
            rpad(row.benefit_geography, 6),
            ": ",
            row.total_avoided_ch4_t / 1_000_000,
            " Mt CH4 avoided -> ",
            row.net_temperature_deaths_avoided,
            " net temperature-related deaths avoided through ",
            row.impact_horizon
        )
    end

    scenario_money = filter(
        row ->
            row.scenario_id == scenario_string,
        monetary_summary
    )

    println()
    println("Monetary benefits, 5-trial test means:")

    for geography in unique(
        scenario_money.benefit_geography
    )

        geo_results = filter(
            row ->
                row.benefit_geography == geography,
            scenario_money
        )

        println()
        println("  ", geography)

        for row in eachrow(geo_results)

            println(
                "    ",
                rpad(row.metric, 38),
                ": ",
                row.mean_avoided_benefit_usd2005 / 1_000_000,
                " million USD2005"
            )
        end
    end
end

println()
println("Saved policy outputs:")
println("  ", MONETARY_BY_YEAR_PATH)
println("  ", MONETARY_SUMMARY_PATH)
println("  ", MORTALITY_BY_ABATEMENT_YEAR_PATH)
println("  ", MORTALITY_SUMMARY_PATH)
println("  ", MORTALITY_BY_IMPACT_YEAR_PATH)

println()
println("IMPORTANT:")
println(
    "Monetary results use only 5 aligned Monte Carlo trials and are proof-of-concept values."
)
println(
    "EU27 and German monetised totals exclude agriculture."
)
println(
    "Physical mortality covers net temperature-related mortality only, not methane-induced ozone mortality."
)