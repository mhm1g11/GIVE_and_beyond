using Mimi

using MimiGIVE

using DataFrames

using FileIO

using CSVFiles

using Random

using Statistics

using JSON

using Dates

include(joinpath(@__DIR__, "config.jl"))

include(joinpath(@__DIR__, "../src/ResearchClimateProduction.jl"))

const RCP = ResearchClimateProduction

const VALUATION_YEAR = START_YEAR

const MODEL_START_YEAR = 1750

const LOCAL_ROOT = joinpath(RELEASE_CONFIG.output_dir, "policy_scenarios")

# GIVE DamageAggregator outputs are already in USD2005/year.

# Agriculture, energy, and labour are converted to USD inside the model aggregators.

# CIAM policy differences are converted to total USD2005/year below by multiplying

# its normalized USD-per-tonne output by 1e6 for the 1 Mt normalization.

const GLOBAL_CHANNELS = (

    :temperature_mortality,

    :agriculture,

    :energy,

    :labor,

    :total_excluding_slr,

    :slr,

    :total_climate

)

const DAMAGE_VARS = Dict(

    :temperature_mortality => :cromar_mortality_damage,

    :agriculture => :agriculture_damage,

    :energy => :energy_damage,

    :labor => :labor_damage,

    :total_excluding_slr => :total_damage

)

const EU27_SET = Set(EU27)

function parse_mode()

    modes = [
        ("--data-smoke", :data_smoke),
        ("--production", :production)
    ]

    selected = [mode for (flag, mode) in modes if flag in ARGS]

    length(selected) == 1 ||
        error("Use exactly one mode: --data-smoke or --production")

    return only(selected)

end

function load_design(mode)

    design = MimiGIVE.load_labor_trial_design(

        RELEASE_CONFIG.labor_design,

        RELEASE_CONFIG.trial_design

    )

    sort!(design, :trialnum)

    design.trialnum == collect(1:nrow(design)) ||

        error("Trial design must contain consecutive trial numbers 1:N.")

    if mode in (:smoke, :zero_smoke, :data_smoke)

        nrow(design) >= 2 || error("Smoke test requires at least two aligned trials.")

        return design[1:2, :]

    end

    nrow(design) == POLICY_N_TRIALS ||

        error("Production expects exactly $POLICY_N_TRIALS aligned trials.")

    return design

end

function load_scenario(path::String, label::String)

    isfile(path) || error("Missing final scenario file: $path")

    df = DataFrame(load(path))

    required = [:year, :avoided_ch4_mt]

    all(c -> c in propertynames(df), required) ||
        error("$label must contain columns year and avoided_ch4_mt.")

    out = select(df, :year, :avoided_ch4_mt)

    any(ismissing, out.year) &&
        error("$label contains missing years.")

    any(ismissing, out.avoided_ch4_mt) &&
        error("$label contains missing avoided_ch4_mt.")

    out.year = Int.(out.year)
    out.avoided_ch4_mt = Float64.(out.avoided_ch4_mt)

    all(isfinite, out.avoided_ch4_mt) ||
        error("$label contains non-finite mitigation values.")

    all(out.avoided_ch4_mt .>= 0.0) ||
        error("$label must contain non-negative avoided methane.")

    length(unique(out.year)) == nrow(out) ||
        error("$label contains duplicate years.")

    all(out.year .<= FULL_MODEL_HORIZON) ||
        error("$label contains years after the supported scenario horizon $FULL_MODEL_HORIZON.")

    sort!(out, :year)

    # External CSVs must supply every valuation year; synthetic smoke inputs
    # bypass this loader and may intentionally contain only a few years.
    missing_years = setdiff(VALUATION_YEAR:FULL_MODEL_HORIZON, out.year)
    isempty(missing_years) ||
        error("$label must cover every year from $VALUATION_YEAR through $FULL_MODEL_HORIZON; missing years: $missing_years.")

    return out
end

function load_scenarios(mode)
    # All modes consume user inputs; smoke limits trials, never substitutes policy.
    return Dict(s.name => load_scenario(s.path, s.name) for s in RELEASE_CONFIG.scenarios)
end

function scenario_addition(df::DataFrame, years::Vector{Int})

    addition = zeros(Float64, length(years))

    model_start = first(years)
    model_end = last(years)

    for row in eachrow(df)

        year = Int(row.year)

        # Preserve pre-model/pre-valuation rows in the source scenario for
        # provenance, but they do not enter the GIVE policy perturbation.
        if year < model_start || year < VALUATION_YEAR
            continue
        end

        year <= model_end ||
            error("Scenario year $year lies after the model horizon.")

        idx = findfirst(==(year), years)

        isnothing(idx) &&
            error("Scenario year $year is not a model year.")

        addition[idx] = -Float64(row.avoided_ch4_mt)
    end

    # Use the explicit external pathway through FULL_MODEL_HORIZON (2300).
    # No internal extrapolation after the final supplied year.
    return addition
end

function activation_year(m, years::Vector{Int})

    d = m[:antarctic_icesheet, :disintegration_volume]

    idx = findfirst(x -> !ismissing(x) && x > 0, d)

    return isnothing(idx) ? missing : years[idx]

end

function geography_mask(countries::Vector{String}, geography::String)

    if geography == "globe"

        return trues(length(countries))

    elseif geography == "EU27"

        return in.(countries, Ref(EU27_SET))

    elseif geography == "DEU"

        return countries .== GERMANY

    else

        error("Unknown geography: $geography")

    end

end

# Project Ramsey discounting: VALUATION_YEAR comes from the scenario configuration.
# Factors vary by Monte Carlo trial and ISO/Lancet formulation, using baseline
# global net consumption per person (:global_netconsumption, :net_cpc).
# PRTP and ETA come from config.jl and retain the Moore et al. (2026) central
# approximately 2% near-term consumption discounting specification. The 2%
# describes the consumption-growth-dependent outcome, NOT PRTP itself.
# DF_i,r,t = (C_i,r,valuation / C_i,r,t)^ETA * (1 + PRTP)^(-(t - valuation_year)).
function discount_vector(cpc, years::Vector{Int}, idx::Vector{Int})

    valuation_idx = findfirst(==(VALUATION_YEAR), years)

    isnothing(valuation_idx) &&

        error("Valuation year is not in model time.")

    cpc0 = Float64(cpc[valuation_idx])

    isfinite(cpc0) && cpc0 > 0 ||

        error("Invalid valuation-year net consumption.")

    vals = Float64.(cpc[idx])

    all(x -> isfinite(x) && x > 0, vals) ||

        error("Invalid baseline net consumption.")

    return (cpc0 ./ vals).^ETA ./

        (1 + PRTP).^(years[idx] .- VALUATION_YEAR)

end

function summary_stats(

    table::DataFrame,

    keys::Vector{Symbol},

    value_col::Symbol

)

    rows = DataFrame()

    for g in groupby(table, keys)

        x = Float64.(g[!, value_col])

        row = NamedTuple{Tuple(keys)}(

            Tuple(g[1, k] for k in keys)

        )

        stats = (

            mean=mean(x),

            median=median(x),

            p05=quantile(x, 0.05),

            p95=quantile(x, 0.95),

            se=std(x) / sqrt(length(x)),

            n=length(x)

        )

        push!(rows, merge(row, stats); cols=:union)

    end

    return rows

end

function main()

    mode = parse_mode()

    GAS == :CH4 ||

        error("This runner is configured for CH4 only.")

    INCLUDE_LABOR ||

        error("Labour extension must be enabled.")

    FULL_MODEL_HORIZON == 2300 ||

        error("Expected full model horizon 2300.")

    Set(LABOR_RESPONSES) == Set((:ISO, :Lancet)) ||

        error("Expected ISO and Lancet labour responses.")

    PRTP == exp(0.001972641) - 1 ||

        error("Unexpected PRTP.")

    ETA == 1.244458999 ||

        error("Unexpected eta.")

    design = load_design(mode)

    scenarios = load_scenarios(mode)

    output_dir = joinpath(

        LOCAL_ROOT,

        String(mode)

    )

    ispath(output_dir) && error("Output already exists; choose a new output_dir: $output_dir")

    mkpath(output_dir)

    input_copy_dir = joinpath(

        output_dir,

        "scenario_inputs"

    )

    mkpath(input_copy_dir)

    for (label, df) in scenarios

        save(

            joinpath(

                input_copy_dir,

                "$(label).csv"

            ),

            df

        )

    end

    pv_rows = DataFrame()

    annual_rows = DataFrame()

    mortality_annual_rows = DataFrame()

    mortality_pv_rows = DataFrame()

    slr_threshold_rows = DataFrame()

    qa_rows = DataFrame()
    discount_rows = DataFrame(
        trialnum=Int[], labor_response=String[], year=Int[], discount_factor=Float64[]
    )

    physical_reference =

        Dict{Tuple{Int,String},DataFrame}()

    slr_reference =

        Dict{Tuple{Int,String},Vector{Float64}}()

    climate_reference =

        Dict{Int,Vector{Float64}}()

    policy_climate_reference =

        Dict{Tuple{Int,String},Vector{Float64}}()

    started = now()

    for response in LABOR_RESPONSES

        println()

        println("====================================================")

        println("POLICY PATH RUN: ", response, " / ", mode)

        println("Trials: ", nrow(design))

        println("====================================================")

        flush(stdout)

        model = RCP.climate_model(response=response)

        mm = MimiGIVE.get_marginal_model(

            model;

            year=VALUATION_YEAR,

            gas=:CH4,

            pulse_size=1.0

        )

        years = Int.(

            Mimi.dim_keys(

                mm.base,

                :time

            )

        )

        years == collect(first(years):last(years)) ||

            error("Model time dimension must be annual and consecutive.")

        first(years) == MODEL_START_YEAR ||

            error("Unexpected model start year.")

        FULL_MODEL_HORIZON <= last(years) ||

            error("Model ends before the requested horizon.")

        impact_idx = findall(

            y -> VALUATION_YEAR <= y <= FULL_MODEL_HORIZON,

            years

        )

        impact_years = years[impact_idx]

        countries = String.(

            Mimi.dim_keys(

                mm.base,

                :country

            )

        )

        issubset(EU27_SET, Set(countries)) ||

            error("Model country dimension is missing EU27 members.")

        GERMANY in countries ||

            error("Germany is missing from model country dimension.")

        additions = Dict(

            label => scenario_addition(

                df,

                years

            )

            for (label, df) in scenarios

        )

        labels = sort(

            collect(keys(additions))

        )

        first_label = first(labels)

        ciam_base = nothing

        ciam_modified = nothing

        fingerprints = nothing

        if response == :ISO

            ciam_base, fingerprints =

                MimiGIVE.get_ciam(mm.base)

            ciam_modified, _ =

                MimiGIVE.get_ciam(mm.base)

            ciam_base =

                Mimi.build(ciam_base)

            ciam_modified =

                Mimi.build(ciam_modified)

        end

        Random.seed!(RELEASE_CONFIG.seed)

        sim = MimiGIVE.get_mcs(

            nrow(design);

            fair_parameter_set=:deterministic,

            fair_parameter_set_ids=

                Int.(design.fair_parameter_set_id),

            rffsp_sampling=:deterministic,

            rffsp_sampling_ids=

                Int.(design.rffsp_id),

            Agriculture_gtap=

                MimiGIVE._get_mooreag_gtap(model)

        )

        MimiGIVE.add_labor_draws!(

            sim,

            Int.(design.labor_model_id)

        )

        pre = (s, i, n, t) ->

            Mimi.update_param!(

                s.models[2].mi,

                Mimi.get_model_param_name(

                    s.models[2].mi.md,

                    :marginalemission,

                    :add

                ),

                additions[first_label]

            )

        function post(s, trial, n, t)

            base, modified = s.models

            design_row =

                design[trial, :]

            Int(base[:Labor, :gcm]) ==

                Int(modified[:Labor, :gcm]) ==

                Int(design_row.labor_model_id) ||

                error(

                    "Labour-model alignment failed for trial $trial."

                )

            base_temp =

                Float64.(

                    base[:temperature, :T]

                )

            if response == :ISO

                climate_reference[trial] =

                    copy(base_temp)

            else

                haskey(

                    climate_reference,

                    trial

                ) ||

                    error(

                        "Missing ISO climate reference for trial $trial."

                    )

                isequal(

                    base_temp,

                    climate_reference[trial]

                ) ||

                    error(

                        "Climate trajectory differs between ISO and Lancet for trial $trial."

                    )

            end

            cpc =

                base[

                    :global_netconsumption,

                    :net_cpc

                ]

            discount =

                discount_vector(

                    cpc,

                    years,

                    impact_idx

                )
            # Export the same baseline factors used below, once per trial/response.
            for (j, year) in enumerate(impact_years)
                push!(discount_rows, (
                    trialnum=Int(design_row.trialnum),
                    labor_response=String(response), year=year,
                    discount_factor=discount[j]
                ))
            end

            base_activation =

                activation_year(

                    base,

                    years

                )

            function evaluate(

                label::String,

                addition::Vector{Float64};

                already_run::Bool=false

            )

                if !already_run

                    Mimi.update_param!(

                        modified.mi,

                        Mimi.get_model_param_name(

                            modified.mi.md,

                            :marginalemission,

                            :add

                        ),

                        addition

                    )

                    run(modified)

                end

                isequal(

                    base[:Socioeconomic, :gdp],

                    modified[:Socioeconomic, :gdp]

                ) ||

                    error(

                        "GDP changed between baseline and policy for trial $trial / $label."

                    )

                isequal(

                    base[:Socioeconomic, :population],

                    modified[:Socioeconomic, :population]

                ) ||

                    error(

                        "Population changed between baseline and policy for trial $trial / $label."

                    )

                isequal(

                    base[:VSL, :vsl],

                    modified[:VSL, :vsl]

                ) ||

                    error(

                        "VSL changed between baseline and policy for trial $trial / $label."

                    )

                policy_temp =

                    Float64.(

                        modified[

                            :temperature,

                            :T

                        ]

                    )

                policy_temp_key =

                    (trial, label)

                if response == :ISO

                    policy_climate_reference[

                        policy_temp_key

                    ] = copy(policy_temp)

                else

                    haskey(

                        policy_climate_reference,

                        policy_temp_key

                    ) ||

                        error(

                            "Missing ISO policy-climate reference for trial $trial / $label."

                        )

                    isequal(

                        policy_temp,

                        policy_climate_reference[

                            policy_temp_key

                        ]

                    ) ||

                        error(

                            "Policy climate differs between ISO and Lancet for trial $trial / $label."

                        )

                end

                actual =

                    Float64.(

                        modified[

                            :marginalemission,

                            :output

                        ]

                    ) .-

                    Float64.(

                        base[

                            :ch4_emissions_identity,

                            :output_ch4

                        ]

                    )

                emissions_error =

                    maximum(

                        abs.(

                            actual .- addition

                        )

                    )

                emissions_error <= 1e-10 ||

                    error(

                        "Emissions QA failed for trial $trial / $label: $emissions_error"

                    )

                all(

                    iszero,

                    actual[

                        addition .== 0.0

                    ]

                ) ||

                    error(

                        "Emissions changed outside requested years for trial $trial / $label."

                    )

                fair_input =

                    modified[

                        :ch4_cycle,

                        Symbol("fossil_emiss_CH\u2084")

                    ]

                isequal(

                    fair_input,

                    modified[

                        :marginalemission,

                        :output

                    ]

                ) ||

                    error(

                        "FaIR CH4 input is not connected to the requested policy path."

                    )

                pre_start =

                    findall(

                        <(VALUATION_YEAR),

                        years

                    )

                isequal(

                    base[

                        :temperature,

                        :T

                    ][pre_start],

                    modified[

                        :temperature,

                        :T

                    ][pre_start]

                ) ||

                    error(

                        "Policy changes temperature before valuation year."

                    )

                annual =

                    Dict{

                        Symbol,

                        Vector{Float64}

                    }()

                for (channel, var) in DAMAGE_VARS

                    annual[channel] =

                        Float64.(

                            base[

                                :DamageAggregator,

                                var

                            ][impact_idx]

                        ) .-

                        Float64.(

                            modified[

                                :DamageAggregator,

                                var

                            ][impact_idx]

                        )

                end

                isapprox(

                    annual[

                        :total_excluding_slr

                    ],

                    annual[

                        :temperature_mortality

                    ] .+

                    annual[

                        :agriculture

                    ] .+

                    annual[

                        :energy

                    ] .+

                    annual[

                        :labor

                    ];

                    rtol=1e-8,

                    atol=1e-2

                ) ||

                    error(

                        "Non-SLR sector reconciliation failed for trial $trial / $label."

                    )

                slr_key =

                    (trial, label)

                if response == :ISO

                    ci =

                        MimiGIVE._compute_ciam_marginal_damages(

                            base,

                            modified,

                            :CH4,

                            ciam_base,

                            ciam_modified,

                            fingerprints;

                            CIAM_foresight=:perfect,

                            CIAM_GDPcap=false,

                            pulse_size=1.0

                        )

                    # For the policy-path comparison we retain CIAM's

                    # perfect-foresight adaptation response from the valuation

                    # year onwards. Unlike GIVE's standard one-year pulse SCC

                    # calculation, we do not zero the valuation-year CIAM

                    # difference. The mitigation pathway is treated as a known

                    # alternative future, so adaptation decisions may respond

                    # immediately to lower anticipated future sea-level rise.

                    slr_full =

                        -Float64.(

                            ci.globe

                        ) .* 1e6

                    slr =

                        slr_full[

                            impact_idx

                        ]

                    slr_reference[

                        slr_key

                    ] = copy(slr)

                else

                    haskey(

                        slr_reference,

                        slr_key

                    ) ||

                        error(

                            "Missing ISO SLR reference for trial $trial / $label."

                        )

                    slr =

                        copy(

                            slr_reference[

                                slr_key

                            ]

                        )

                end

                annual[:slr] =

                    slr

                annual[:total_climate] =

                    annual[

                        :total_excluding_slr

                    ] .+

                    annual[:slr]

                all(

                    v -> all(

                        isfinite,

                        v

                    ),

                    values(annual)

                ) ||

                    error(

                        "Non-finite monetary benefits for trial $trial / $label."

                    )

                base_deaths =

                    Float64.(

                        base[

                            :CromarMortality,

                            :excess_deaths

                        ][

                            impact_idx,

                            :

                        ]

                    )

                policy_deaths =

                    Float64.(

                        modified[

                            :CromarMortality,

                            :excess_deaths

                        ][

                            impact_idx,

                            :

                        ]

                    )

                avoided_deaths_country =

                    base_deaths .-

                    policy_deaths

                all(

                    isfinite,

                    avoided_deaths_country

                ) ||

                    error(

                        "Non-finite temperature mortality for trial $trial / $label."

                    )

                # Use GIVE's own country-level monetised mortality output directly.

                # CromarMortality.mortality_costs is the exact variable connected to

                # DamageAggregator.damage_cromar_mortality, so regional monetised

                # mortality should be aggregated from this variable rather than

                # reconstructed independently as avoided_deaths * VSL.

                base_mortality_costs =

                    Float64.(

                        base[

                            :CromarMortality,

                            :mortality_costs

                        ][

                            impact_idx,

                            :

                        ]

                    )

                policy_mortality_costs =

                    Float64.(

                        modified[

                            :CromarMortality,

                            :mortality_costs

                        ][

                            impact_idx,

                            :

                        ]

                    )

                all(

                    isfinite,

                    base_mortality_costs

                ) ||

                    error(

                        "Non-finite baseline mortality costs for trial $trial."

                    )

                all(

                    isfinite,

                    policy_mortality_costs

                ) ||

                    error(

                        "Non-finite policy mortality costs for trial $trial / $label."

                    )

                mortality_value_country =

                    base_mortality_costs .-

                    policy_mortality_costs

                # Strong QA against the exact source variable used by DamageAggregator.

                #

                # Use the already-computed maximum absolute annual discrepancies

                # directly. These comparisons involve sums and differences of large

                # floating-point monetary values, so a one-dollar absolute tolerance

                # is more appropriate than an array-norm isapprox check.

                #

                # This remains far tighter than anything material to the policy

                # results and still catches unit or aggregation errors.

                base_global_from_country =

                    vec(

                        sum(

                            base_mortality_costs;

                            dims=2

                        )

                    )

                policy_global_from_country =

                    vec(

                        sum(

                            policy_mortality_costs;

                            dims=2

                        )

                    )

                base_global_aggregator =

                    Float64.(

                        base[

                            :DamageAggregator,

                            :cromar_mortality_damage

                        ][impact_idx]

                    )

                policy_global_aggregator =

                    Float64.(

                        modified[

                            :DamageAggregator,

                            :cromar_mortality_damage

                        ][impact_idx]

                    )

                base_err =

                    maximum(

                        abs.(

                            base_global_from_country .-

                            base_global_aggregator

                        )

                    )

                policy_err =

                    maximum(

                        abs.(

                            policy_global_from_country .-

                            policy_global_aggregator

                        )

                    )

                benefit_residual =
                    vec(
                        sum(
                            mortality_value_country;
                            dims=2
                        )
                    ) .-
                    annual[
                        :temperature_mortality
                    ]

                benefit_err = maximum(abs.(benefit_residual))

                benefit_worst_idx = argmax(abs.(benefit_residual))
                benefit_worst_year = impact_years[benefit_worst_idx]
                benefit_worst_signed_residual = benefit_residual[benefit_worst_idx]

                base_err <= 1.0 ||

                    error(

                        "Baseline country mortality costs do not reconcile with DamageAggregator " *

                        "for trial $trial. Maximum absolute error = $base_err USD2005/year."

                    )

                policy_err <= 1.0 ||

                    error(

                        "Policy country mortality costs do not reconcile with DamageAggregator " *

                        "for trial $trial / $label. Maximum absolute error = $policy_err USD2005/year."

                    )

                physical =

                    DataFrame(

                        year=Int[],

                        geography=String[],

                        avoided_deaths=Float64[],

                        monetised_usd2005=Float64[],

                        discounted_monetised_usd2005=

                            Float64[]

                    )

                for geography in (

                    "globe",

                    "EU27",

                    "DEU"

                )

                    mask =

                        geography_mask(

                            countries,

                            geography

                        )

                    for (j, year) in enumerate(

                        impact_years

                    )

                        deaths =

                            sum(

                                avoided_deaths_country[

                                    j,

                                    mask

                                ]

                            )

                        money =

                            sum(

                                mortality_value_country[

                                    j,

                                    mask

                                ]

                            )

                        push!(

                            physical,

                            (

                                year=year,

                                geography=geography,

                                avoided_deaths=deaths,

                                monetised_usd2005=money,

                                discounted_monetised_usd2005=

                                    money *

                                    discount[j]

                            )

                        )

                    end

                end

                phys_key =

                    (trial, label)

                if response == :ISO

                    physical_reference[

                        phys_key

                    ] =

                        select(

                            physical,

                            :year,

                            :geography,

                            :avoided_deaths

                        )

                else

                    ref =

                        physical_reference[

                            phys_key

                        ]

                    cur =

                        select(

                            physical,

                            :year,

                            :geography,

                            :avoided_deaths

                        )

                    isequal(

                        select(

                            ref,

                            [

                                :year,

                                :geography

                            ]

                        ),

                        select(

                            cur,

                            [

                                :year,

                                :geography

                            ]

                        )

                    ) ||

                        error(

                            "ISO/Lancet mortality coverage differs for trial $trial / $label."

                        )

                    all(

                        isapprox.(

                            ref.avoided_deaths,

                            cur.avoided_deaths;

                            rtol=1e-10,

                            atol=1e-10

                        )

                    ) ||

                        error(

                            "Physical temperature mortality differs between ISO and Lancet."

                        )

                end

                policy_activation =

                    activation_year(

                        modified,

                        years

                    )

                if mode == :zero_smoke

                    maximum(abs.(addition)) <= 1e-15 ||
                        error("Zero-smoke scenario contains a non-zero methane addition for trial $trial / $label.")

                    maximum(abs.(actual)) <= 1e-12 ||
                        error("Zero-smoke emissions response is non-zero for trial $trial / $label.")

                    maximum(abs.(policy_temp .- base_temp)) <= 1e-12 ||
                        error("Zero-smoke temperature response is non-zero for trial $trial / $label.")

                    for (channel, stream) in annual
                        max_abs = maximum(abs.(stream))
                        max_abs <= 1e-6 ||
                            error(
                                "Zero-smoke monetary channel $(channel) is non-zero for trial $trial / $label. " *
                                "Maximum absolute annual value = $max_abs USD2005/year."
                            )
                    end

                    maximum(abs.(avoided_deaths_country)) <= 1e-12 ||
                        error("Zero-smoke physical temperature mortality is non-zero for trial $trial / $label.")

                    maximum(abs.(mortality_value_country)) <= 1e-6 ||
                        error("Zero-smoke monetised temperature mortality is non-zero for trial $trial / $label.")

                    base_activation == policy_activation ||
                        error("Zero-smoke changed the sea-level threshold activation year for trial $trial / $label.")

                end

                return (

                    annual=annual,

                    physical=physical,

                    discount=discount,

                    emissions_error=

                        emissions_error,

                    requested_change=

                        sum(addition),

                    actual_change=

                        sum(actual),

                    baseline_activation=

                        base_activation,

                    policy_activation=

                        policy_activation,
                    mortality_base_reconciliation_max_abs_usd2005_per_year=base_err,
                    mortality_policy_reconciliation_max_abs_usd2005_per_year=policy_err,
                    mortality_benefit_reconciliation_max_abs_usd2005_per_year=benefit_err,
                    mortality_benefit_reconciliation_worst_year=benefit_worst_year,
                    mortality_benefit_reconciliation_worst_signed_usd2005_per_year=benefit_worst_signed_residual

                )

            end

            for (position, label) in enumerate(labels)

                result =

                    evaluate(

                        label,

                        additions[label];

                        already_run=(

                            position == 1 &&

                            label == first_label

                        )

                    )

                identity = (

                    scenario=label,

                    labor_response=

                        String(response),

                    trialnum=

                        Int(

                            design_row.trialnum

                        ),

                    rffsp_id=

                        Int(

                            design_row.rffsp_id

                        ),

                    fair_parameter_set_id=

                        Int(

                            design_row.fair_parameter_set_id

                        ),

                    labor_model_id=

                        Int(

                            design_row.labor_model_id

                        )

                )

                for channel in GLOBAL_CHANNELS

                    # Every policy-benefit stream in result.annual

                    # is total USD2005/year.

                    stream_usd =

                        result.annual[

                            channel

                        ]

                    pv_usd =

                        sum(

                            stream_usd .*

                            result.discount

                        )

                    push!(

                        pv_rows,

                        merge(

                            identity,

                            (

                                geography="globe",

                                channel=

                                    String(

                                        channel

                                    ),

                                value_usd2005_pv_valuation_year=

                                    pv_usd,

                                valuation_year=

                                    VALUATION_YEAR,

                                last_year=

                                    FULL_MODEL_HORIZON

                            )

                        );

                        cols=:union

                    )

                    for j in eachindex(

                        impact_years

                    )

                        push!(

                            annual_rows,

                            merge(

                                identity,

                                (

                                    geography=

                                        "globe",

                                    impact_year=

                                        impact_years[j],

                                    channel=

                                        String(

                                            channel

                                        ),

                                    benefit_usd2005=

                                        stream_usd[j],

                                    discount_factor=

                                        result.discount[j],

                                    discounted_benefit_usd2005=

                                        stream_usd[j] *

                                        result.discount[j]

                                )

                            );

                            cols=:union

                        )

                    end

                end

                for row in eachrow(

                    result.physical

                )

                    push!(

                        mortality_annual_rows,

                        merge(

                            identity,

                            (

                                impact_year=

                                    Int(

                                        row.year

                                    ),

                                geography=

                                    String(

                                        row.geography

                                    ),

                                avoided_deaths=

                                    Float64(

                                        row.avoided_deaths

                                    ),

                                monetised_usd2005=

                                    Float64(

                                        row.monetised_usd2005

                                    ),

                                discount_factor=

                                    result.discount[

                                        findfirst(

                                            ==(

                                                Int(

                                                    row.year

                                                )

                                            ),

                                            impact_years

                                        )

                                    ],

                                discounted_monetised_usd2005=

                                    Float64(

                                        row.discounted_monetised_usd2005

                                    )

                            )

                        );

                        cols=:union

                    )

                end

                for geography in (

                    "globe",

                    "EU27",

                    "DEU"

                )

                    rows =

                        result.physical[

                            result.physical.geography .==

                            geography,

                            :

                        ]

                    push!(

                        mortality_pv_rows,

                        merge(

                            identity,

                            (

                                geography=

                                    geography,

                                avoided_deaths=

                                    sum(

                                        rows.avoided_deaths

                                    ),

                                monetised_mortality_usd2005_pv_valuation_year=

                                    sum(

                                        rows.discounted_monetised_usd2005

                                    ),

                                valuation_year=

                                    VALUATION_YEAR,

                                last_year=

                                    FULL_MODEL_HORIZON

                            )

                        );

                        cols=:union

                    )

                end

                if response == :ISO

                    push!(

                        slr_threshold_rows,

                        merge(

                            identity,

                            (

                                baseline_activation_year=

                                    result.baseline_activation,

                                policy_activation_year=

                                    result.policy_activation,

                                threshold_year_change=

                                    ismissing(

                                        result.baseline_activation

                                    ) ||

                                    ismissing(

                                        result.policy_activation

                                    ) ?

                                    missing :

                                    Int(

                                        result.policy_activation

                                    ) -

                                    Int(

                                        result.baseline_activation

                                    )

                            )

                        );

                        cols=:union

                    )

                end

                push!(

                    qa_rows,

                    merge(

                        identity,

                        (

                            max_emissions_error_mt=

                                result.emissions_error,

                            requested_net_change_mt=

                                result.requested_change,

                            actual_net_change_mt=

                                result.actual_change,
                            mortality_base_reconciliation_max_abs_usd2005_per_year=result.mortality_base_reconciliation_max_abs_usd2005_per_year,
                            mortality_policy_reconciliation_max_abs_usd2005_per_year=result.mortality_policy_reconciliation_max_abs_usd2005_per_year,
                            mortality_benefit_reconciliation_max_abs_usd2005_per_year=result.mortality_benefit_reconciliation_max_abs_usd2005_per_year,
                            mortality_benefit_reconciliation_worst_year=result.mortality_benefit_reconciliation_worst_year,
                            mortality_benefit_reconciliation_worst_signed_usd2005_per_year=result.mortality_benefit_reconciliation_worst_signed_usd2005_per_year,

                            all_checks_passed=true

                        )

                    );

                    cols=:union

                )

                println(

                    response,

                    " trial ",

                    trial,

                    " ",

                    label,

                    " PASS"

                )

                flush(stdout)

            end

        end

        trial_file =

            joinpath(

                output_dir,

                "sampled_parameters_$(response).csv"

            )

        run(

            sim,

            [

                mm.base,

                mm.modified

            ],

            nrow(design);

            pre_trial_func=pre,

            post_trial_func=post,

            results_in_memory=false,

            trials_output_filename=

                trial_file

        )

        GC.gc()

    end

    iso_trial_file =

        joinpath(

            output_dir,

            "sampled_parameters_ISO.csv"

        )

    lancet_trial_file =

        joinpath(

            output_dir,

            "sampled_parameters_Lancet.csv"

        )

    read(iso_trial_file) ==

        read(lancet_trial_file) ||

        error(

            "ISO and Lancet sampled parameter files differ."

        )

    sort!(

        pv_rows,

        [

            :scenario,

            :labor_response,

            :trialnum,

            :channel

        ]

    )

    sort!(

        annual_rows,

        [

            :scenario,

            :labor_response,

            :trialnum,

            :impact_year,

            :channel

        ]

    )

    sort!(

        mortality_annual_rows,

        [

            :scenario,

            :labor_response,

            :trialnum,

            :geography,

            :impact_year

        ]

    )

    sort!(

        mortality_pv_rows,

        [

            :scenario,

            :labor_response,

            :trialnum,

            :geography

        ]

    )

    sort!(

        slr_threshold_rows,

        [

            :scenario,

            :trialnum

        ]

    )

    sort!(

        qa_rows,

        [

            :scenario,

            :labor_response,

            :trialnum

        ]

    )

    save(

        joinpath(

            output_dir,

            "global_monetised_pv_trials.csv"

        ),

        pv_rows

    )

    save(

        joinpath(

            output_dir,

            "global_monetised_annual_trials.csv"

        ),

        annual_rows

    )

    save(

        joinpath(

            output_dir,

            "temperature_mortality_annual_trials_by_response.csv"

        ),

        mortality_annual_rows

    )

    save(

        joinpath(

            output_dir,

            "temperature_mortality_pv_trials_by_response.csv"

        ),

        mortality_pv_rows

    )

    save(

        joinpath(

            output_dir,

            "slr_threshold_trials.csv"

        ),

        slr_threshold_rows

    )

    save(

        joinpath(

            output_dir,

            "emissions_qa.csv"

        ),

        qa_rows

    )

    global_stats =

        summary_stats(

            pv_rows,

            [

                :scenario,

                :labor_response,

                :geography,

                :channel

            ],

            :value_usd2005_pv_valuation_year

        )

    save(

        joinpath(

            output_dir,

            "global_monetised_summary_by_response.csv"

        ),

        global_stats

    )

    mortality_stats =

        summary_stats(

            mortality_pv_rows,

            [

                :scenario,

                :labor_response,

                :geography

            ],

            :monetised_mortality_usd2005_pv_valuation_year

        )

    save(

        joinpath(

            output_dir,

            "temperature_mortality_monetised_summary_by_response.csv"

        ),

        mortality_stats

    )

    physical_iso =

        mortality_annual_rows[

            mortality_annual_rows.labor_response .==

            "ISO",

            :

        ]

    physical_cumulative =

        combine(

            groupby(

                physical_iso,

                [

                    :scenario,

                    :trialnum,

                    :rffsp_id,

                    :fair_parameter_set_id,

                    :labor_model_id,

                    :geography

                ]

            ),

            :avoided_deaths =>

                sum =>

                :avoided_deaths

        )

    save(

        joinpath(

            output_dir,

            "temperature_mortality_annual_trials.csv"

        ),

        select(

            physical_iso,

            Not(

                [

                    :labor_response,

                    :monetised_usd2005,

                    :discount_factor,

                    :discounted_monetised_usd2005

                ]

            )

        )

    )

    save(

        joinpath(

            output_dir,

            "temperature_mortality_cumulative_trials.csv"

        ),

        physical_cumulative

    )

    central_global =

        DataFrame()

    for g in groupby(

        global_stats,

        [

            :scenario,

            :geography,

            :channel

        ]

    )

        Set(g.labor_response) ==

            Set(

                [

                    "ISO",

                    "Lancet"

                ]

            ) ||

            error(

                "Central global result requires both labour responses."

            )

        iso =

            g[

                g.labor_response .==

                "ISO",

                :

            ][1, :]

        lancet =

            g[

                g.labor_response .==

                "Lancet",

                :

            ][1, :]

        push!(

            central_global,

            (

                scenario=

                    g.scenario[1],

                geography=

                    g.geography[1],

                channel=

                    g.channel[1],

                statistic=

                    "mean_of_ISO_Lancet_means",

                value_usd2005_pv_valuation_year=

                    (

                        Float64(

                            iso.mean

                        ) +

                        Float64(

                            lancet.mean

                        )

                    ) / 2,

                valuation_year=

                    VALUATION_YEAR,

                last_year=

                    FULL_MODEL_HORIZON,

                n_trials_per_response=

                    Int(iso.n)

            )

        )

    end

    save(

        joinpath(

            output_dir,

            "global_monetised_central_means.csv"

        ),

        central_global

    )

    central_mortality =

        DataFrame()

    for g in groupby(

        mortality_stats,

        [

            :scenario,

            :geography

        ]

    )

        Set(g.labor_response) ==

            Set(

                [

                    "ISO",

                    "Lancet"

                ]

            ) ||

            error(

                "Central mortality result requires both labour responses."

            )

        iso =

            g[

                g.labor_response .==

                "ISO",

                :

            ][1, :]

        lancet =

            g[

                g.labor_response .==

                "Lancet",

                :

            ][1, :]

        push!(

            central_mortality,

            (

                scenario=

                    g.scenario[1],

                geography=

                    g.geography[1],

                statistic=

                    "mean_of_ISO_Lancet_means",

                monetised_mortality_usd2005_pv_valuation_year=

                    (

                        Float64(

                            iso.mean

                        ) +

                        Float64(

                            lancet.mean

                        )

                    ) / 2,

                valuation_year=

                    VALUATION_YEAR,

                last_year=

                    FULL_MODEL_HORIZON,

                n_trials_per_response=

                    Int(iso.n)

            )

        )

    end

    save(

        joinpath(

            output_dir,

            "temperature_mortality_monetised_central_means.csv"

        ),

        central_mortality

    )

    save(joinpath(output_dir, "give_discount_factors_trials.csv"), discount_rows)
    open(joinpath(output_dir, "give_discount_factors_metadata.json"), "w") do io
        JSON.print(io, Dict(
            "PRTP" => PRTP,
            "ETA" => ETA,
            "valuation_year" => VALUATION_YEAR,
            "discounting_specification" => "Moore et al. (2026) central Ramsey; approximately 2% near-term consumption rate; equity weighting disabled. DF = (C_valuation / C_t)^ETA / (1 + PRTP)^(t - valuation_year).",
            "baseline_consumption_definition" => "Trial- and labour-response-specific baseline global net consumption per person, GIVE :global_netconsumption => :net_cpc; the exact baseline vector used in policy PV calculations.",
            "first_year" => VALUATION_YEAR,
            "last_year" => FULL_MODEL_HORIZON,
            "labor_responses" => String.(collect(LABOR_RESPONSES)),
            "scenario_independent" => true
        ), 2)
    end

    metadata =

        Dict(

            "status" =>

                "PASS",

            "mode" =>

                String(mode),

            "scenario_input_horizon" =>
                maximum(vcat([df.year for df in values(scenarios)]...)),
            "post_scenario_horizon_treatment" =>
                mode in (:smoke, :zero_smoke) ?
                    "Synthetic scenario values only; no internal post-input extrapolation." :
                    "Explicit external policy pathway supplied through $FULL_MODEL_HORIZON; no internal post-input extrapolation.",
            "zero_smoke_boundary_condition" =>
                mode == :zero_smoke ?
                    "Zero methane mitigation required to produce zero emissions, temperature, monetary-damage, physical-mortality, monetised-mortality, and SLR-threshold differences within strict numerical tolerances." :
                    "not applicable",

            "n_trials" =>

                nrow(design),

            "valuation_year" =>

                VALUATION_YEAR,

            "last_year" =>

                FULL_MODEL_HORIZON,

            "prtp" =>

                PRTP,

            "eta" =>

                ETA,

            "gas" =>

                String(GAS),

            "labor_responses" =>

                String.(

                    collect(

                        LABOR_RESPONSES

                    )

                ),

            "scenarios" =>

                sort(

                    collect(

                        keys(

                            scenarios

                        )

                    )

                ),

            "CIAM_foresight" =>

                "perfect",

            "CIAM_GDPcap" =>

                false,

            "CIAM_valuation_year_treatment" =>

                "Perfect-foresight adaptation differences are retained from the valuation year onward for the full policy-path comparison.",

            "slr_computed_under" =>

                "ISO annual stream, reused under Lancet with Lancet discounting after climate equality QA",

            "physical_temperature_mortality" =>

                "ISO retained after exact ISO/Lancet equality QA",

            "exported_monetary_unit" =>

                "USD2005",

            "internal_damage_stream_unit" =>

                "USD2005 per year",

            "started" =>

                string(started),

            "finished" =>

                string(now())

        )

    open(

        joinpath(

            output_dir,

            "validation.json"

        ),

        "w"

    ) do io

        JSON.print(

            io,

            metadata,

            2

        )

    end

    println()

    println("====================================================")

    println("POLICY PATH RUN COMPLETE")

    println("Mode: ", mode)

    println("Output: ", output_dir)

    println("====================================================")

end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
