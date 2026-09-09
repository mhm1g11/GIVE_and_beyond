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
# Paths
# =====================================================================

const POLICY_INPUT = joinpath(
    INPUT_DIR,
    "mock_methane_abatement.csv"
)

const TRIAL_DESIGN_PATH = joinpath(
    INPUT_DIR,
    "mc_trial_design.csv"
)

const GIVE_TRIAL_LIBRARY = joinpath(
    OUTPUT_DIR,
    "monetary_impact_library_trials.csv"
)

const OZONE_TRIAL_LIBRARY = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_impact_library_trials.csv"
)

const BY_YEAR_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_expanded_by_abatement_year_trials.csv"
)

const TRIAL_TOTAL_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_expanded_trials.csv"
)

const SUMMARY_OUTPUT = joinpath(
    POLICY_RESULT_DIR,
    "policy_monetary_expanded_summary.csv"
)

mkpath(
    POLICY_RESULT_DIR
)

println("APPLYING FULLY ALIGNED GIVE + OZONE MONETARY TRIALS")
println("===================================================")
println()

# =====================================================================
# Helpers
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


function give_total_metric(
    geography::String
)

    if geography == "globe"

        return "total_monetised"

    else

        return "total_monetised_excl_agriculture"
    end
end


function give_component_metrics(
    geography::String
)

    if geography == "globe"

        return [
            "temperature_mortality_monetised",
            "agriculture_monetised",
            "energy_monetised",
            "slr_monetised"
        ]

    else

        return [
            "temperature_mortality_monetised",
            "energy_monetised",
            "slr_monetised"
        ]
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

trial_design =
    DataFrame(
        load(
            TRIAL_DESIGN_PATH
        )
    )

give_trials =
    DataFrame(
        load(
            GIVE_TRIAL_LIBRARY
        )
    )

ozone_trials =
    DataFrame(
        load(
            OZONE_TRIAL_LIBRARY
        )
    )

# =====================================================================
# Normalise types
# =====================================================================

abatement.year =
    as_int.(
        abatement.year
    )

abatement.avoided_ch4_t =
    as_float.(
        abatement.avoided_ch4_t
    )

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

give_trials.pulse_year =
    as_int.(
        give_trials.pulse_year
    )

give_trials.trialnum =
    as_int.(
        give_trials.trialnum
    )

give_trials.rffsp_id =
    as_int.(
        give_trials.rffsp_id
    )

give_trials.fair_parameter_set_id =
    as_int.(
        give_trials.fair_parameter_set_id
    )

give_trials.value =
    as_float.(
        give_trials.value
    )

ozone_trials.pulse_year =
    as_int.(
        ozone_trials.pulse_year
    )

ozone_trials.trialnum =
    as_int.(
        ozone_trials.trialnum
    )

ozone_trials.rffsp_id =
    as_int.(
        ozone_trials.rffsp_id
    )

ozone_trials.fair_parameter_set_id =
    as_int.(
        ozone_trials.fair_parameter_set_id
    )

ozone_trials.ozone_mortality_monetised_usd2005_per_t_ch4 =
    as_float.(
        ozone_trials.ozone_mortality_monetised_usd2005_per_t_ch4
    )

sort!(
    trial_design,
    :trialnum
)

const N_TRIALS =
    nrow(
        trial_design
    )

# =====================================================================
# 1. Trial alignment QA
# =====================================================================

println("TRIAL ALIGNMENT QA")
println("==================")
println()

for row in eachrow(
    trial_design
)

    trialnum =
        Int(
            row.trialnum
        )

    expected_rff =
        Int(
            row.rffsp_id
        )

    expected_fair =
        Int(
            row.fair_parameter_set_id
        )

    give_rows = filter(
        r ->
            r.trialnum ==
            trialnum,
        give_trials
    )

    ozone_rows = filter(
        r ->
            r.trialnum ==
            trialnum,
        ozone_trials
    )

    nrow(give_rows) > 0 ||
        error(
            "No GIVE rows for trial $trialnum."
        )

    nrow(ozone_rows) > 0 ||
        error(
            "No ozone rows for trial $trialnum."
        )

    give_rff =
        unique(
            give_rows.rffsp_id
        )

    give_fair =
        unique(
            give_rows.fair_parameter_set_id
        )

    ozone_rff =
        unique(
            ozone_rows.rffsp_id
        )

    ozone_fair =
        unique(
            ozone_rows.fair_parameter_set_id
        )

    length(give_rff) == 1 ||
        error(
            "Multiple GIVE RFF IDs in trial $trialnum."
        )

    length(give_fair) == 1 ||
        error(
            "Multiple GIVE FaIR IDs in trial $trialnum."
        )

    length(ozone_rff) == 1 ||
        error(
            "Multiple ozone RFF IDs in trial $trialnum."
        )

    length(ozone_fair) == 1 ||
        error(
            "Multiple ozone FaIR IDs in trial $trialnum."
        )

    give_rff[1] == expected_rff ||
        error(
            "GIVE RFF mismatch in trial $trialnum."
        )

    ozone_rff[1] == expected_rff ||
        error(
            "Ozone RFF mismatch in trial $trialnum."
        )

    give_fair[1] == expected_fair ||
        error(
            "GIVE FaIR mismatch in trial $trialnum."
        )

    ozone_fair[1] == expected_fair ||
        error(
            "Ozone FaIR mismatch in trial $trialnum."
        )

    println(
        "Trial ",
        trialnum,
        ": RFF ",
        expected_rff,
        " | FaIR ",
        expected_fair,
        " | GIVE + ozone PASS"
    )
end

println()

# =====================================================================
# 2. Build lookup dictionaries
# =====================================================================

give_lookup =
    Dict{
        Tuple{
            Int,
            String,
            Int,
            String
        },
        Float64
    }()

for row in eachrow(
    give_trials
)

    key = (
        Int(
            row.pulse_year
        ),
        string(
            row.geography
        ),
        Int(
            row.trialnum
        ),
        string(
            row.metric
        )
    )

    haskey(
        give_lookup,
        key
    ) &&
        error(
            "Duplicate GIVE key: $key"
        )

    give_lookup[
        key
    ] =
        Float64(
            row.value
        )
end


ozone_lookup =
    Dict{
        Tuple{
            Int,
            String,
            Int
        },
        Float64
    }()

for row in eachrow(
    ozone_trials
)

    key = (
        Int(
            row.pulse_year
        ),
        string(
            row.geography
        ),
        Int(
            row.trialnum
        )
    )

    haskey(
        ozone_lookup,
        key
    ) &&
        error(
            "Duplicate ozone key: $key"
        )

    ozone_lookup[
        key
    ] =
        Float64(
            row.ozone_mortality_monetised_usd2005_per_t_ch4
        )
end

# =====================================================================
# 3. Apply methane abatement scenario
# =====================================================================

by_year = DataFrame(
    scenario_id = String[],
    abatement_scope = String[],
    abatement_year = Int[],
    benefit_geography = String[],
    trialnum = Int[],
    rffsp_id = Int[],
    fair_parameter_set_id = Int[],
    avoided_ch4_t = Float64[],
    metric = String[],
    value_per_t_ch4 = Float64[],
    benefit_usd2005 = Float64[]
)

for policy_row in eachrow(
    abatement
)

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

    for geography in benefit_geographies(
        scope
    )

        base_total_metric =
            give_total_metric(
                geography
            )

        component_metrics =
            give_component_metrics(
                geography
            )

        for trial_row in eachrow(
            trial_design
        )

            trialnum =
                Int(
                    trial_row.trialnum
                )

            rffsp_id =
                Int(
                    trial_row.rffsp_id
                )

            fair_id =
                Int(
                    trial_row.fair_parameter_set_id
                )

            # =========================================================
            # GIVE component benefits
            # =========================================================

            component_sum_per_t =
                0.0

            for metric in component_metrics

                key = (
                    pulse_year,
                    geography,
                    trialnum,
                    metric
                )

                haskey(
                    give_lookup,
                    key
                ) ||
                    error(
                        "Missing GIVE factor: $key"
                    )

                factor =
                    give_lookup[
                        key
                    ]

                component_sum_per_t +=
                    factor

                push!(
                    by_year,
                    (
                        scenario_id,
                        scope,
                        pulse_year,
                        geography,
                        trialnum,
                        rffsp_id,
                        fair_id,
                        avoided_ch4_t,
                        metric,
                        factor,
                        avoided_ch4_t *
                        factor
                    )
                )
            end

            # =========================================================
            # Official GIVE total
            # =========================================================

            total_key = (
                pulse_year,
                geography,
                trialnum,
                base_total_metric
            )

            haskey(
                give_lookup,
                total_key
            ) ||
                error(
                    "Missing GIVE total: $total_key"
                )

            give_total_per_t =
                give_lookup[
                    total_key
                ]

            push!(
                by_year,
                (
                    scenario_id,
                    scope,
                    pulse_year,
                    geography,
                    trialnum,
                    rffsp_id,
                    fair_id,
                    avoided_ch4_t,
                    "give_total",
                    give_total_per_t,
                    avoided_ch4_t *
                    give_total_per_t
                )
            )

            # =========================================================
            # GIVE reconciliation residual
            # =========================================================

            residual_per_t =
                give_total_per_t -
                component_sum_per_t

            push!(
                by_year,
                (
                    scenario_id,
                    scope,
                    pulse_year,
                    geography,
                    trialnum,
                    rffsp_id,
                    fair_id,
                    avoided_ch4_t,
                    "give_interaction_residual",
                    residual_per_t,
                    avoided_ch4_t *
                    residual_per_t
                )
            )

            # =========================================================
            # Ozone respiratory mortality
            # =========================================================

            ozone_key = (
                pulse_year,
                geography,
                trialnum
            )

            haskey(
                ozone_lookup,
                ozone_key
            ) ||
                error(
                    "Missing ozone factor: $ozone_key"
                )

            ozone_per_t =
                ozone_lookup[
                    ozone_key
                ]

            push!(
                by_year,
                (
                    scenario_id,
                    scope,
                    pulse_year,
                    geography,
                    trialnum,
                    rffsp_id,
                    fair_id,
                    avoided_ch4_t,
                    "ozone_mortality_monetised",
                    ozone_per_t,
                    avoided_ch4_t *
                    ozone_per_t
                )
            )

            # =========================================================
            # Expanded total
            # =========================================================

            expanded_per_t =
                give_total_per_t +
                ozone_per_t

            push!(
                by_year,
                (
                    scenario_id,
                    scope,
                    pulse_year,
                    geography,
                    trialnum,
                    rffsp_id,
                    fair_id,
                    avoided_ch4_t,
                    "expanded_total",
                    expanded_per_t,
                    avoided_ch4_t *
                    expanded_per_t
                )
            )
        end
    end
end

sort!(
    by_year,
    [
        :scenario_id,
        :benefit_geography,
        :trialnum,
        :metric,
        :abatement_year
    ]
)

# =====================================================================
# 4. Sum policy years within each aligned trial
# =====================================================================

trial_totals = combine(
    groupby(
        by_year,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :trialnum,
            :rffsp_id,
            :fair_parameter_set_id,
            :metric
        ]
    ),

    :benefit_usd2005 =>
        sum =>
        :benefit_usd2005
)

sort!(
    trial_totals,
    [
        :scenario_id,
        :benefit_geography,
        :metric,
        :trialnum
    ]
)

# =====================================================================
# 5. Monte Carlo summary
# =====================================================================

summary = combine(
    groupby(
        trial_totals,
        [
            :scenario_id,
            :abatement_scope,
            :benefit_geography,
            :metric
        ]
    ),

    :benefit_usd2005 =>
        mean =>
        :mean_usd2005,

    :benefit_usd2005 =>
        median =>
        :median_usd2005,

    :benefit_usd2005 =>
        (
            x ->
                quantile(
                    x,
                    0.025
                )
        ) =>
        :p2_5_usd2005,

    :benefit_usd2005 =>
        (
            x ->
                quantile(
                    x,
                    0.10
                )
        ) =>
        :p10_usd2005,

    :benefit_usd2005 =>
        (
            x ->
                quantile(
                    x,
                    0.90
                )
        ) =>
        :p90_usd2005,

    :benefit_usd2005 =>
        (
            x ->
                quantile(
                    x,
                    0.975
                )
        ) =>
        :p97_5_usd2005,

    nrow =>
        :n_trials
)

sort!(
    summary,
    [
        :scenario_id,
        :benefit_geography,
        :metric
    ]
)

# =====================================================================
# 6. Expanded-total QA
#
# Expanded total is constructed as GIVE + ozone at each abatement year
# and then summed across years.
#
# Mathematically:
#
#   sum(GIVE_y + ozone_y)
#
# should equal:
#
#   sum(GIVE_y) + sum(ozone_y)
#
# Tiny floating-point differences can arise from summation order, so
# we use a strict relative tolerance rather than a sub-micro-dollar
# absolute tolerance.
# =====================================================================

println("EXPANDED TOTAL QA")
println("=================")
println()

scenario_ids =
    unique(
        trial_totals.scenario_id
    )

max_abs_difference =
    Ref(0.0)

max_rel_difference =
    Ref(0.0)

for scenario_id in scenario_ids

    scenario_rows = filter(
        row ->
            row.scenario_id ==
            scenario_id,
        trial_totals
    )

    geographies =
        unique(
            scenario_rows.benefit_geography
        )

    for geography in geographies

        for trialnum in 1:N_TRIALS

            rows = filter(
                row ->
                    row.benefit_geography ==
                        geography &&
                    row.trialnum ==
                        trialnum,
                scenario_rows
            )

            give_row = filter(
                row ->
                    row.metric ==
                    "give_total",
                rows
            )

            ozone_row = filter(
                row ->
                    row.metric ==
                    "ozone_mortality_monetised",
                rows
            )

            expanded_row = filter(
                row ->
                    row.metric ==
                    "expanded_total",
                rows
            )

            nrow(give_row) == 1 ||
                error(
                    "Missing GIVE total QA row for " *
                    "$scenario_id / $geography / trial $trialnum."
                )

            nrow(ozone_row) == 1 ||
                error(
                    "Missing ozone QA row for " *
                    "$scenario_id / $geography / trial $trialnum."
                )

            nrow(expanded_row) == 1 ||
                error(
                    "Missing expanded QA row for " *
                    "$scenario_id / $geography / trial $trialnum."
                )

            give_value =
                Float64(
                    give_row.benefit_usd2005[1]
                )

            ozone_value =
                Float64(
                    ozone_row.benefit_usd2005[1]
                )

            expanded_value =
                Float64(
                    expanded_row.benefit_usd2005[1]
                )

            expected_value =
                give_value +
                ozone_value

            difference =
                expanded_value -
                expected_value

            scale =
                max(
                    abs(expanded_value),
                    abs(expected_value),
                    1.0
                )

            relative_difference =
                abs(
                    difference
                ) /
                scale

            max_abs_difference[] =
                max(
                    max_abs_difference[],
                    abs(
                        difference
                    )
                )

            max_rel_difference[] =
                max(
                    max_rel_difference[],
                    relative_difference
                )

            if !isapprox(
                expanded_value,
                expected_value;
                rtol = 1e-12,
                atol = 1e-4
            )

                error(
                    "Expanded total QA failed for " *
                    "$scenario_id / $geography / trial $trialnum.\n" *
                    "  GIVE:     $give_value\n" *
                    "  Ozone:    $ozone_value\n" *
                    "  Expected: $expected_value\n" *
                    "  Expanded: $expanded_value\n" *
                    "  Abs diff: $difference\n" *
                    "  Rel diff: $relative_difference"
                )
            end
        end
    end
end

println(
    "Maximum absolute numerical difference: ",
    max_abs_difference[],
    " USD2005"
)

println(
    "Maximum relative numerical difference: ",
    max_rel_difference[]
)

println(
    "PASS: expanded total = GIVE total + ozone in every trial."
)

println()

# =====================================================================
# 7. Console results
# =====================================================================

println("FULLY ALIGNED POLICY MONETARY RESULTS")
println("=====================================")
println()

for scenario_id in scenario_ids

    println(
        scenario_id
    )

    println(
        repeat(
            "-",
            length(
                scenario_id
            )
        )
    )

    scenario_summary = filter(
        row ->
            row.scenario_id ==
            scenario_id,
        summary
    )

    geographies =
        unique(
            scenario_summary.benefit_geography
        )

    for geography in geographies

        println()
        println(
            "  ",
            geography
        )

        geo_summary = filter(
            row ->
                row.benefit_geography ==
                geography,
            scenario_summary
        )

        for metric in [
            "give_total",
            "ozone_mortality_monetised",
            "expanded_total"
        ]

            metric_row = filter(
                row ->
                    row.metric ==
                    metric,
                geo_summary
            )

            nrow(
                metric_row
            ) == 1 ||
                continue

            label =
                metric ==
                "give_total" ?
                    "GIVE total" :
                metric ==
                "ozone_mortality_monetised" ?
                    "Ozone respiratory" :
                    "Expanded total"

            println(
                "    ",
                rpad(
                    label,
                    20
                ),
                ": mean ",
                round(
                    metric_row.mean_usd2005[1] /
                    1e6,
                    digits = 3
                ),
                " | median ",
                round(
                    metric_row.median_usd2005[1] /
                    1e6,
                    digits = 3
                ),
                " million USD2005"
            )
        end

        expanded_row = filter(
            row ->
                row.metric ==
                "expanded_total",
            geo_summary
        )

        if nrow(
            expanded_row
        ) == 1

            println(
                "    Test p10-p90       : ",
                round(
                    expanded_row.p10_usd2005[1] /
                    1e6,
                    digits = 3
                ),
                " to ",
                round(
                    expanded_row.p90_usd2005[1] /
                    1e6,
                    digits = 3
                ),
                " million USD2005"
            )
        end
    end

    println()
end

# =====================================================================
# 8. Save
# =====================================================================

save(
    BY_YEAR_OUTPUT,
    by_year
)

save(
    TRIAL_TOTAL_OUTPUT,
    trial_totals
)

save(
    SUMMARY_OUTPUT,
    summary
)

println()
println("Saved:")

println(
    "  ",
    BY_YEAR_OUTPUT
)

println(
    "  ",
    TRIAL_TOTAL_OUTPUT
)

println(
    "  ",
    SUMMARY_OUTPUT
)

println()
println("IMPORTANT")
println("=========")

println(
    "GIVE and ozone monetary benefits are now combined trial by trial."
)

println(
    "Each trial uses the same explicit RFF socioeconomic and FaIR IDs " *
    "defined in mc_trial_design.csv."
)

println(
    "The ozone-health calibration itself is still fixed at McDuffie's " *
    "central estimate."
)

println(
    "With only ",
    N_TRIALS,
    " trials, percentile estimates are diagnostic only."
)