using Random
using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics
using JSON
using Dates
include(joinpath(@__DIR__, "..", "src", "MethaneOzoneMortality.jl"))
using .MethaneOzoneMortality
include(joinpath(@__DIR__, "config.jl"))
const VALUATION_YEAR = START_YEAR
const MC_SEED = RELEASE_CONFIG.seed
const MOMM_ROOT = RELEASE_CONFIG.momm_root
const MOMM_SOCIO_PATH = RELEASE_CONFIG.momm_socio
const LOCAL_ROOT = joinpath(RELEASE_CONFIG.output_dir, "policy_ozone")
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
function as_int(x)
    x isa Integer && return Int(x)
    return parse(Int, strip(string(x)))
end
function as_float_or_missing(x)
    ismissing(x) && return missing
    if x isa Real
        value = Float64(x)
        return isfinite(value) ? value : missing
    end
    value = strip(string(x))
    isempty(value) && return missing
    lowercase(value) in ["missing", "na", "n/a", "nan"] && return missing
    parsed = parse(Float64, value)
    return isfinite(parsed) ? parsed : missing
end
function find_column(df::DataFrame, candidates::Vector{Symbol})
    available = propertynames(df)
    for candidate in candidates
        candidate in available && return candidate
    end
    error(
        "Could not find any of $(candidates). Available columns are $(available)."
    )
end
function geography_subset(df::DataFrame, geography::String)
    if geography == "globe"
        return df
    elseif geography == "EU27"
        return filter(
            row -> !isempty(row.iso3) && row.iso3 in EU27,
            df
        )
    elseif geography == "DEU"
        return filter(
            row -> row.iso3 == GERMANY,
            df
        )
    else
        error("Unknown geography: $geography")
    end
end
function load_design(mode)
    design = MimiGIVE.load_labor_trial_design(
        RELEASE_CONFIG.labor_design,
        RELEASE_CONFIG.trial_design
    )
    design.trialnum = as_int.(design.trialnum)
    design.rffsp_id = as_int.(design.rffsp_id)
    design.fair_parameter_set_id =
        as_int.(design.fair_parameter_set_id)
    design.labor_model_id =
        as_int.(design.labor_model_id)
    sort!(design, :trialnum)
    design.trialnum == collect(1:nrow(design)) ||
        error(
            "labor_trial_design.csv must contain consecutive trial numbers 1:N."
        )
    if mode in (:smoke, :zero_smoke, :data_smoke)
        nrow(design) >= 2 ||
            error("Smoke test requires at least two aligned trials.")
        return design[1:2, :]
    end
    nrow(design) == POLICY_N_TRIALS ||
        error("Production expects exactly $POLICY_N_TRIALS aligned trials.")
    return design
end
function load_scenario(path::String, label::String)
    isfile(path) ||
        error("Missing final scenario file: $path")

    df = DataFrame(load(path))
    required = [:year, :avoided_ch4_mt]

    all(c -> c in propertynames(df), required) ||
        error(
            "$label must contain columns year and avoided_ch4_mt."
        )

    out = select(
        df,
        :year,
        :avoided_ch4_mt
    )

    any(ismissing, out.year) &&
        error("$label contains missing years.")

    any(ismissing, out.avoided_ch4_mt) &&
        error("$label contains missing avoided_ch4_mt.")

    out.year = Int.(out.year)
    out.avoided_ch4_mt =
        Float64.(out.avoided_ch4_mt)

    all(isfinite, out.avoided_ch4_mt) ||
        error("$label contains non-finite mitigation values.")

    all(out.avoided_ch4_mt .>= 0.0) ||
        error(
            "$label must contain non-negative avoided methane."
        )

    length(unique(out.year)) == nrow(out) ||
        error("$label contains duplicate years.")

    all(out.year .<= FULL_MODEL_HORIZON) ||
        error(
            "$label contains years after the supported scenario horizon $FULL_MODEL_HORIZON."
        )

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

function scenario_addition(
    df::DataFrame,
    years::Vector{Int}
)
    addition = zeros(Float64, length(years))

    model_start = first(years)
    model_end = last(years)

    for row in eachrow(df)
        year = Int(row.year)

        # Retain pre-valuation rows in the copied source scenario for
        # provenance, but exclude them from the GIVE policy perturbation.
        if year < model_start || year < VALUATION_YEAR
            continue
        end

        year <= model_end ||
            error("Scenario year $year lies after the model horizon.")

        idx = findfirst(
            ==(year),
            years
        )

        isnothing(idx) &&
            error(
                "Scenario year $year is not a model year."
            )

        addition[idx] =
            -Float64(row.avoided_ch4_mt)
    end

    # Use the explicit external pathway through FULL_MODEL_HORIZON (2300).
    # No internal extrapolation after the final supplied year.
    return addition
end
function clean_country_variable(
    df::DataFrame,
    value_candidates::Vector{Symbol},
    output_value::Symbol
)
    trial_col = find_column(
        df,
        [:trialnum, :trial, :trial_number]
    )
    time_col = find_column(
        df,
        [:time, :year]
    )
    country_col = find_column(
        df,
        [:country, :countries]
    )
    value_col = find_column(
        df,
        value_candidates
    )
    clean = select(
        df,
        trial_col => :trialnum,
        time_col => :year,
        country_col => :iso3,
        value_col => output_value
    )
    clean.trialnum =
        as_int.(clean.trialnum)
    clean.year =
        as_int.(clean.year)
    clean.iso3 = [
        ismissing(x) ? "" : strip(string(x))
        for x in clean.iso3
    ]
    clean[!, output_value] =
        as_float_or_missing.(clean[!, output_value])
    return clean
end
function clean_global_cpc(df::DataFrame)
    trial_col = find_column(
        df,
        [:trialnum, :trial, :trial_number]
    )
    time_col = find_column(
        df,
        [:time, :year]
    )
    value_col = find_column(
        df,
        [:net_cpc]
    )
    clean = select(
        df,
        trial_col => :trialnum,
        time_col => :year,
        value_col => :global_net_cpc
    )
    clean.trialnum =
        as_int.(clean.trialnum)
    clean.year =
        as_int.(clean.year)
    clean.global_net_cpc =
        as_float_or_missing.(clean.global_net_cpc)
    return clean
end
function build_cpc_lookup(df::DataFrame)
    lookup =
        Dict{Tuple{Int,Int},Float64}()
    for row in eachrow(df)
        if !ismissing(row.global_net_cpc)
            lookup[
                (
                    Int(row.trialnum),
                    Int(row.year)
                )
            ] =
                Float64(row.global_net_cpc)
        end
    end
    return lookup
end
function discount_factor(
    lookup,
    trialnum::Int,
    impact_year::Int,
    label::String
)
    impact_year < VALUATION_YEAR &&
        return 0.0
    valuation_key =
        (trialnum, VALUATION_YEAR)
    impact_key =
        (trialnum, impact_year)
    haskey(lookup, valuation_key) ||
        error(
            "Missing $label CPC for trial $trialnum, valuation year $VALUATION_YEAR."
        )
    haskey(lookup, impact_key) ||
        error(
            "Missing $label CPC for trial $trialnum, year $impact_year."
        )
    cpc0 =
        lookup[valuation_key]
    cpct =
        lookup[impact_key]
    return (
        (cpc0 / cpct)^ETA /
        (1 + PRTP)^(impact_year - VALUATION_YEAR)
    )
end
function build_trial_socio(
    trial_design::DataFrame,
    output_dir::String
)
    rffsp_ids =
        collect(trial_design.rffsp_id)
    fair_ids =
        collect(trial_design.fair_parameter_set_id)
    labor_ids =
        collect(trial_design.labor_model_id)
    n_trials =
        nrow(trial_design)
    mcs_dir =
        joinpath(output_dir, "mcs_inputs")
    ispath(mcs_dir) && error("MC output already exists: $mcs_dir")
    println(
        "Running aligned GIVE socioeconomic inputs for ozone..."
    )
    flush(stdout)
    m_iso = MimiGIVE.get_model(
        include_labor=true,
        labor_response=:ISO
    )
    Random.seed!(MC_SEED)
    mcs_iso = MimiGIVE.run_mcs(
        trials=n_trials,
        m=m_iso,
        fair_parameter_set=:deterministic,
        fair_parameter_set_ids=fair_ids,
        rffsp_sampling=:deterministic,
        rffsp_sampling_ids=rffsp_ids,
        labor_model_ids=labor_ids,
        save_list=[
            (:Socioeconomic, :population),
            (:Socioeconomic, :deathrate),
            (:VSL, :vsl),
            (:global_netconsumption, :net_cpc)
        ],
        output_dir=joinpath(
            mcs_dir,
            "iso"
        ),
        results_in_memory=true
    )
    m_lancet = MimiGIVE.get_model(
        include_labor=true,
        labor_response=:Lancet
    )
    Random.seed!(MC_SEED)
    mcs_lancet = MimiGIVE.run_mcs(
        trials=n_trials,
        m=m_lancet,
        fair_parameter_set=:deterministic,
        fair_parameter_set_ids=fair_ids,
        rffsp_sampling=:deterministic,
        rffsp_sampling_ids=rffsp_ids,
        labor_model_ids=labor_ids,
        save_list=[
            (:global_netconsumption, :net_cpc)
        ],
        output_dir=joinpath(
            mcs_dir,
            "lancet"
        ),
        results_in_memory=true
    )
    population =
        clean_country_variable(
            getdataframe(
                mcs_iso,
                :Socioeconomic,
                :population
            ),
            [:population],
            :give_population_millions
        )
    deathrate =
        clean_country_variable(
            getdataframe(
                mcs_iso,
                :Socioeconomic,
                :deathrate
            ),
            [:deathrate],
            :give_deathrate_per_thousand
        )
    vsl =
        clean_country_variable(
            getdataframe(
                mcs_iso,
                :VSL,
                :vsl
            ),
            [:vsl],
            :give_vsl_usd2005
        )
    cpc_iso =
        clean_global_cpc(
            getdataframe(
                mcs_iso,
                :global_netconsumption,
                :net_cpc
            )
        )
    cpc_lancet =
        clean_global_cpc(
            getdataframe(
                mcs_lancet,
                :global_netconsumption,
                :net_cpc
            )
        )
    for df in (
        population,
        deathrate,
        vsl
    )
        filter!(
            row ->
                2020 <=
                row.year <=
                IMPACT_HORIZON,
            df
        )
    end
    filter!(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        cpc_iso
    )
    filter!(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        cpc_lancet
    )
    return (
        population=population,
        deathrate=deathrate,
        vsl=vsl,
        cpc_iso=cpc_iso,
        cpc_lancet=cpc_lancet
    )
end
function build_socio_lookup(inputs)
    isfile(MOMM_SOCIO_PATH) ||
        error(
            "Missing McDuffie socioeconomic reference file: $MOMM_SOCIO_PATH"
        )
    momm_socio =
        DataFrame(load(MOMM_SOCIO_PATH))
    momm_socio.year =
        as_int.(momm_socio.year)
    momm_socio.reference_population_thousands =
        as_float_or_missing.(
            momm_socio.reference_population_thousands
        )
    momm_socio.reference_allcause_mortality_rate =
        as_float_or_missing.(
            momm_socio.reference_allcause_mortality_rate
        )
    momm_socio.iso3_clean = [
        ismissing(x) ? "" : strip(string(x))
        for x in momm_socio.iso3
    ]
    momm_valid =
        filter(
            row -> !isempty(row.iso3_clean),
            momm_socio
        )
    duplicates =
        combine(
            groupby(
                momm_valid,
                [:iso3_clean, :year]
            ),
            nrow => :n
        )
    any(duplicates.n .> 1) &&
        error(
            "Duplicate mapped McDuffie ISO3/year rows found."
        )
    give_socio =
        leftjoin(
            inputs.population,
            inputs.deathrate,
            on=[:trialnum, :year, :iso3]
        )
    give_socio =
        leftjoin(
            give_socio,
            inputs.vsl,
            on=[:trialnum, :year, :iso3]
        )
    momm_join =
        select(
            momm_valid,
            :iso3_clean => :iso3,
            :year,
            :reference_population_thousands,
            :reference_allcause_mortality_rate
        )
    trial_socio =
        leftjoin(
            give_socio,
            momm_join,
            on=[:iso3, :year]
        )
    lookup =
        Dict{
            Tuple{Int,String,Int},
            NamedTuple
        }()
    for row in eachrow(trial_socio)
        pop_ok =
            !ismissing(
                row.give_population_millions
            ) &&
            !ismissing(
                row.reference_population_thousands
            ) &&
            row.reference_population_thousands > 0
        mort_ok =
            !ismissing(
                row.give_deathrate_per_thousand
            ) &&
            !ismissing(
                row.reference_allcause_mortality_rate
            ) &&
            row.reference_allcause_mortality_rate > 0
        socio_scale = 1.0
        socio_match = false
        if pop_ok && mort_ok
            momm_population_millions =
                Float64(
                    row.reference_population_thousands
                ) / 1000
            give_mortality_rate =
                Float64(
                    row.give_deathrate_per_thousand
                ) / 1000
            socio_scale =
                Float64(
                    row.give_population_millions
                ) /
                momm_population_millions *
                give_mortality_rate /
                Float64(
                    row.reference_allcause_mortality_rate
                )
            socio_match = true
        end
        lookup[
            (
                Int(row.trialnum),
                string(row.iso3),
                Int(row.year)
            )
        ] = (
            socioeconomic_scale=socio_scale,
            give_socio_match=socio_match,
            give_vsl_usd2005=
                row.give_vsl_usd2005
        )
    end
    return lookup
end
function atmosphere_for_scenario(
    reference,
    scenario::DataFrame,
    label::String,
    mode::Symbol
)
    m_det =
        MimiGIVE.get_model()
    mm =
        MimiGIVE.get_marginal_model(
            m_det;
            year=VALUATION_YEAR,
            gas=:CH4,
            pulse_size=1.0
        )
    model_years =
        Int.(dim_keys(mm.base, :time))
    addition =
        scenario_addition(
            scenario,
            model_years
        )
    # Mimi's ModelInstance (\\`.mi\\`) does not exist immediately after
    # get_marginal_model(). Build and run both models first.
    #
    # The first modified run contains the default 1 Mt marginal pulse
    # created by get_marginal_model(). It is used only to build the
    # modified ModelInstance. Its results are discarded.
    run(mm.base)
    run(mm.modified)
    isnothing(mm.base.mi) &&
        error(
            "Baseline GIVE model instance was not built for ozone scenario $label."
        )
    isnothing(mm.modified.mi) &&
        error(
            "Modified GIVE model instance was not built for ozone scenario $label."
        )
    # Replace the default marginal pulse with the complete policy
    # methane pathway. Values are negative because the policy reduces
    # methane emissions relative to the GIVE baseline.
    Mimi.update_param!(
        mm.modified.mi,
        Mimi.get_model_param_name(
            mm.modified.mi.md,
            :marginalemission,
            :add
        ),
        addition
    )
    # Rerun the modified model using the complete policy pathway.
    run(mm.modified)
    actual =
        Float64.(
            mm.modified[
                :marginalemission,
                :output
            ]
        ) .-
        Float64.(
            mm.base[
                :ch4_emissions_identity,
                :output_ch4
            ]
        )
    error_mt =
        maximum(
            abs.(actual .- addition)
        )
    error_mt <= 1e-10 ||
        error(
            "Ozone atmosphere emissions QA failed for $label: $error_mt"
        )
    fair_input =
        mm.modified[
            :ch4_cycle,
            Symbol("fossil_emiss_CH\u2084")
        ]
    isequal(
        fair_input,
        mm.modified[
            :marginalemission,
            :output
        ]
    ) ||
        error(
            "Ozone atmosphere FaIR CH4 input is not connected to the policy path."
        )
    delta_ch4 =
        Float64.(
            mm.modified[
                :ch4_cycle,
                Symbol("CH\u2084")
            ]
        ) .-
        Float64.(
            mm.base[
                :ch4_cycle,
                Symbol("CH\u2084")
            ]
        )
    # A methane-reduction pathway must not increase atmospheric CH4
    # over the ozone impact period, apart from negligible floating-point
    # noise.
    years =
        collect(
            2020:IMPACT_HORIZON
        )
    indices = [
        findfirst(
            ==(year),
            model_years
        )
        for year in years
    ]
    any(isnothing, indices) &&
        error(
            "Required ozone year is missing from GIVE."
        )
    give_delta = [
        delta_ch4[Int(idx)]
        for idx in indices
    ]
    maximum(give_delta) <= 1e-10 ||
        error(
            "Ozone atmosphere QA failed for $label: methane-reduction pathway produced a positive CH4 concentration perturbation."
        )
    if mode == :zero_smoke
        maximum(abs.(addition)) <= 1e-15 ||
            error("Zero-smoke scenario contains a non-zero methane addition for $label.")
        maximum(abs.(actual)) <= 1e-12 ||
            error("Zero-smoke ozone emissions response is non-zero for $label.")
        maximum(abs.(give_delta)) <= 1e-12 ||
            error("Zero-smoke atmospheric CH4 concentration response is non-zero for $label.")
    end
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
    rename!(
        atmosphere,
        :ozone_respiratory_deaths =>
            :atmosphere_only_deaths
    )
    atmosphere.iso3_clean = [
        ismissing(x) ?
        "" :
        strip(string(x))
        for x in atmosphere.iso3
    ]
    if mode == :zero_smoke
        maximum(abs.(Float64.(atmosphere.atmosphere_only_deaths))) <= 1e-12 ||
            error("Zero-smoke McDuffie atmosphere-only mortality response is non-zero for $label.")
    end
    return (
        atmosphere=atmosphere,
        emissions_error=error_mt,
        requested_net_change_mt=sum(addition),
        actual_net_change_mt=sum(actual),
        max_ch4_concentration_change_ppb=
            maximum(give_delta),
        min_ch4_concentration_change_ppb=
            minimum(give_delta)
    )
end
function summary_stats(
    table::DataFrame,
    keys::Vector{Symbol},
    value_col::Symbol
)
    rows = DataFrame()
    for g in groupby(table, keys)
        x =
            Float64.(g[!, value_col])
        key_values =
            NamedTuple{Tuple(keys)}(
                Tuple(
                    g[1, k]
                    for k in keys
                )
            )
        stats = (
            mean=mean(x),
            median=median(x),
            p05=quantile(x, 0.05),
            p95=quantile(x, 0.95),
            se=std(x) / sqrt(length(x)),
            n=length(x)
        )
        push!(
            rows,
            merge(
                key_values,
                stats
            );
            cols=:union
        )
    end
    return rows
end
function main()
    mode = parse_mode()
    GAS == :CH4 ||
        error(
            "Ozone policy runner is configured for CH4 only."
        )
    IMPACT_HORIZON == 2100 ||
        error(
            "Expected ozone endpoint 2100."
        )
    PRTP == exp(0.001972641) - 1 ||
        error(
            "Unexpected PRTP."
        )
    ETA == 1.244458999 ||
        error(
            "Unexpected eta."
        )
    design =
        load_design(mode)
    scenarios =
        load_scenarios(mode)
    output_dir =
        joinpath(
            LOCAL_ROOT,
            String(mode)
        )
    ispath(output_dir) && error("Output already exists; choose a new output_dir: $output_dir")
    mkpath(output_dir)
    scenario_copy_dir =
        joinpath(
            output_dir,
            "scenario_inputs"
        )
    mkpath(scenario_copy_dir)
    for (label, df) in scenarios
        save(
            joinpath(
                scenario_copy_dir,
                "$(label).csv"
            ),
            df
        )
    end
    started = now()
    inputs =
        build_trial_socio(
            design,
            output_dir
        )
    socio_lookup =
        build_socio_lookup(inputs)
    cpc_iso_lookup =
        build_cpc_lookup(
            inputs.cpc_iso
        )
    cpc_lancet_lookup =
        build_cpc_lookup(
            inputs.cpc_lancet
        )
    reference =
        load_momm_reference(
            MOMM_ROOT
        )
    annual_rows =
        DataFrame()
    pv_rows =
        DataFrame()
    qa_rows =
        DataFrame()
    for label in sort(
        collect(keys(scenarios))
    )
        println()
        println(
            "Ozone full policy path: ",
            label
        )
        flush(stdout)
        atmospheric =
            atmosphere_for_scenario(
                reference,
                scenarios[label],
                label,
                mode
            )
        atmosphere =
            atmospheric.atmosphere
        for trial in eachrow(design)
            trialnum =
                Int(trial.trialnum)
            rffsp_id =
                Int(trial.rffsp_id)
            fair_id =
                Int(
                    trial.fair_parameter_set_id
                )
            labor_id =
                Int(trial.labor_model_id)
            trial_country =
                DataFrame()
            for row in eachrow(atmosphere)
                impact_year =
                    Int(row.year)
                impact_year <
                VALUATION_YEAR &&
                    continue
                iso3 =
                    string(
                        row.iso3_clean
                    )
                atmosphere_deaths =
                    Float64(
                        row.atmosphere_only_deaths
                    )
                key = (
                    trialnum,
                    iso3,
                    impact_year
                )
                socioeconomic_scale =
                    1.0
                give_socio_match =
                    false
                give_vsl =
                    missing
                if !isempty(iso3) &&
                   haskey(
                       socio_lookup,
                       key
                   )
                    values =
                        socio_lookup[key]
                    socioeconomic_scale =
                        values.socioeconomic_scale
                    give_socio_match =
                        values.give_socio_match
                    give_vsl =
                        values.give_vsl_usd2005
                end
                # The policy path is a negative methane perturbation.
                # McDuffie therefore returns negative mortality effects.
                # Report avoided deaths as positive benefits.
                avoided_deaths =
                    -atmosphere_deaths *
                    socioeconomic_scale
                df_iso =
                    discount_factor(
                        cpc_iso_lookup,
                        trialnum,
                        impact_year,
                        "ISO"
                    )
                df_lancet =
                    discount_factor(
                        cpc_lancet_lookup,
                        trialnum,
                        impact_year,
                        "Lancet"
                    )
                vsl_match =
                    !ismissing(give_vsl)
                annual_value =
                    vsl_match ?
                    avoided_deaths *
                    Float64(give_vsl) :
                    missing
                discounted_iso =
                    vsl_match ?
                    Float64(
                        annual_value
                    ) *
                    df_iso :
                    missing
                discounted_lancet =
                    vsl_match ?
                    Float64(
                        annual_value
                    ) *
                    df_lancet :
                    missing
                push!(
                    trial_country,
                    (
                        trialnum=trialnum,
                        rffsp_id=rffsp_id,
                        fair_parameter_set_id=
                            fair_id,
                        labor_model_id=
                            labor_id,
                        scenario=label,
                        impact_year=
                            impact_year,
                        iso3=iso3,
                        atmosphere_only_avoided_deaths=
                            -atmosphere_deaths,
                        socioeconomic_scale=
                            socioeconomic_scale,
                        give_socio_match=
                            give_socio_match,
                        avoided_deaths=
                            avoided_deaths,
                        give_vsl_match=
                            vsl_match,
                        give_vsl_usd2005=
                            give_vsl,
                        monetised_usd2005=
                            annual_value,
                        discount_factor_iso=
                            df_iso,
                        discount_factor_lancet=
                            df_lancet,
                        discounted_usd2005_iso=
                            discounted_iso,
                        discounted_usd2005_lancet=
                            discounted_lancet
                    );
                    cols=:union
                )
            end
            for geography in (
                "globe",
                "EU27",
                "DEU"
            )
                geo =
                    geography_subset(
                        trial_country,
                        geography
                    )
                for g in groupby(
                    geo,
                    :impact_year
                )
                    year =
                        Int(
                            g.impact_year[1]
                        )
                    physical =
                        sum(
                            g.avoided_deaths
                        )
                    annual_money =
                        sum(
                            skipmissing(
                                g.monetised_usd2005
                            )
                        )
                    discounted_iso =
                        sum(
                            skipmissing(
                                g.discounted_usd2005_iso
                            )
                        )
                    discounted_lancet =
                        sum(
                            skipmissing(
                                g.discounted_usd2005_lancet
                            )
                        )
                    push!(
                        annual_rows,
                        (
                            scenario=label,
                            trialnum=trialnum,
                            rffsp_id=rffsp_id,
                            fair_parameter_set_id=
                                fair_id,
                            labor_model_id=
                                labor_id,
                            geography=
                                geography,
                            impact_year=
                                year,
                            avoided_deaths=
                                physical,
                            monetised_usd2005=
                                annual_money,
                            discounted_usd2005_iso=
                                discounted_iso,
                            discounted_usd2005_lancet=
                                discounted_lancet
                        )
                    )
                end
                physical_total =
                    sum(
                        geo.avoided_deaths
                    )
                socio_matched_deaths =
                    sum(
                        row.avoided_deaths
                        for row in eachrow(geo)
                        if row.give_socio_match
                    )
                valued_deaths =
                    sum(
                        row.avoided_deaths
                        for row in eachrow(geo)
                        if row.give_vsl_match
                    )
                socio_coverage =
                    physical_total == 0.0 ?
                    1.0 :
                    socio_matched_deaths /
                    physical_total
                vsl_coverage =
                    physical_total == 0.0 ?
                    1.0 :
                    valued_deaths /
                    physical_total
                pv_iso =
                    sum(
                        skipmissing(
                            geo.discounted_usd2005_iso
                        )
                    )
                pv_lancet =
                    sum(
                        skipmissing(
                            geo.discounted_usd2005_lancet
                        )
                    )
                for (response, pv) in (
                    ("ISO", pv_iso),
                    ("Lancet", pv_lancet)
                )
                    push!(
                        pv_rows,
                        (
                            scenario=label,
                            labor_response=
                                response,
                            trialnum=
                                trialnum,
                            rffsp_id=
                                rffsp_id,
                            fair_parameter_set_id=
                                fair_id,
                            labor_model_id=
                                labor_id,
                            geography=
                                geography,
                            avoided_deaths=
                                physical_total,
                            monetised_ozone_mortality_usd2005_pv_valuation_year=
                                pv,
                            give_socio_coverage_share=
                                socio_coverage,
                            give_vsl_coverage_share=
                                vsl_coverage,
                            valuation_year=
                                VALUATION_YEAR,
                            last_year=
                                IMPACT_HORIZON
                        )
                    )
                end
            end
        end
        push!(
            qa_rows,
            (
                scenario=label,
                max_emissions_error_mt=
                    atmospheric.emissions_error,
                requested_net_change_mt=
                    atmospheric.requested_net_change_mt,
                actual_net_change_mt=
                    atmospheric.actual_net_change_mt,
                max_ch4_concentration_change_ppb=
                    atmospheric.max_ch4_concentration_change_ppb,
                min_ch4_concentration_change_ppb=
                    atmospheric.min_ch4_concentration_change_ppb,
                all_checks_passed=true
            )
        )
        global_phys =
            sum(
                annual_rows[
                    (
                        annual_rows.scenario .==
                        label
                    ) .&
                    (
                        annual_rows.geography .==
                        "globe"
                    ),
                    :avoided_deaths
                ]
            )
        if mode == :zero_smoke
            abs(global_phys) <= 1e-12 ||
                error("Zero-smoke cumulative global avoided ozone deaths are non-zero for $label: $global_phys")
            scenario_annual = annual_rows[
                annual_rows.scenario .== label,
                :
            ]
            maximum(abs.(Float64.(scenario_annual.avoided_deaths))) <= 1e-12 ||
                error("Zero-smoke annual avoided ozone deaths are non-zero for $label.")
            maximum(abs.(Float64.(scenario_annual.monetised_usd2005))) <= 1e-6 ||
                error("Zero-smoke annual monetised ozone mortality is non-zero for $label.")
            maximum(abs.(Float64.(scenario_annual.discounted_usd2005_iso))) <= 1e-6 ||
                error("Zero-smoke discounted ISO ozone mortality is non-zero for $label.")
            maximum(abs.(Float64.(scenario_annual.discounted_usd2005_lancet))) <= 1e-6 ||
                error("Zero-smoke discounted Lancet ozone mortality is non-zero for $label.")
            scenario_pv = pv_rows[
                pv_rows.scenario .== label,
                :
            ]
            maximum(abs.(Float64.(scenario_pv.avoided_deaths))) <= 1e-12 ||
                error("Zero-smoke cumulative avoided ozone deaths are non-zero in PV output for $label.")
            maximum(
                abs.(
                    Float64.(
                        scenario_pv.monetised_ozone_mortality_usd2005_pv_valuation_year
                    )
                )
            ) <= 1e-6 ||
                error("Zero-smoke monetised ozone PV is non-zero for $label.")
        else
            global_phys > 0 ||
                error(
                    "Full policy path does not produce positive cumulative avoided ozone deaths for $label."
                )
        end
        println(
            "  completed ",
            nrow(design),
            " aligned trials"
        )
        flush(stdout)
    end
    sort!(
        annual_rows,
        [
            :scenario,
            :trialnum,
            :geography,
            :impact_year
        ]
    )
    sort!(
        pv_rows,
        [
            :scenario,
            :labor_response,
            :trialnum,
            :geography
        ]
    )
    save(
        joinpath(
            output_dir,
            "ozone_mortality_annual_trials.csv"
        ),
        annual_rows
    )
    save(
        joinpath(
            output_dir,
            "ozone_mortality_pv_trials_by_response.csv"
        ),
        pv_rows
    )
    save(
        joinpath(
            output_dir,
            "emissions_qa.csv"
        ),
        qa_rows
    )
    physical_cumulative =
        combine(
            groupby(
                annual_rows,
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
            "ozone_mortality_cumulative_trials.csv"
        ),
        physical_cumulative
    )
    monetary_stats =
        summary_stats(
            pv_rows,
            [
                :scenario,
                :labor_response,
                :geography
            ],
            :monetised_ozone_mortality_usd2005_pv_valuation_year
        )
    save(
        joinpath(
            output_dir,
            "ozone_mortality_monetised_summary_by_response.csv"
        ),
        monetary_stats
    )
    physical_stats =
        summary_stats(
            physical_cumulative,
            [
                :scenario,
                :geography
            ],
            :avoided_deaths
        )
    save(
        joinpath(
            output_dir,
            "ozone_mortality_physical_summary.csv"
        ),
        physical_stats
    )
    central =
        DataFrame()
    for g in groupby(
        monetary_stats,
        [:scenario, :geography]
    )
        Set(g.labor_response) ==
        Set(["ISO", "Lancet"]) ||
            error(
                "Central ozone result requires ISO and Lancet."
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
            central,
            (
                scenario=
                    g.scenario[1],
                geography=
                    g.geography[1],
                statistic=
                    "mean_of_ISO_Lancet_means",
                monetised_ozone_mortality_usd2005_pv_valuation_year=
                    (
                        Float64(iso.mean) +
                        Float64(lancet.mean)
                    ) / 2,
                valuation_year=
                    VALUATION_YEAR,
                last_year=
                    IMPACT_HORIZON,
                n_trials_per_response=
                    Int(iso.n)
            )
        )
    end
    save(
        joinpath(
            output_dir,
            "ozone_mortality_monetised_central_means.csv"
        ),
        central
    )
    metadata =
        Dict(
            "status" => "PASS",
            "mode" => String(mode),
            "zero_smoke_boundary_condition" =>
                mode == :zero_smoke ?
                "Zero methane mitigation required to produce zero emissions, atmospheric CH4 concentration response, McDuffie ozone mortality response, physical avoided deaths, annual monetised mortality, and discounted monetary PV within strict numerical tolerances." :
                "not applicable",
            "n_trials" => nrow(design),
            "valuation_year" =>
                VALUATION_YEAR,
            "last_year" =>
                IMPACT_HORIZON,
            "scenario_input_horizon" =>
                maximum(vcat([df.year for df in values(scenarios)]...)),
            "post_scenario_horizon_treatment" =>
                mode in (:smoke, :zero_smoke) ?
                    "Synthetic scenario values only; no internal hold-final extrapolation. Ozone impacts evaluated through $IMPACT_HORIZON." :
                    "Explicit external policy pathway supplied through $FULL_MODEL_HORIZON; ozone impacts evaluated through $IMPACT_HORIZON; no internal hold-final extrapolation.",
            "pre_valuation_scenario_treatment" =>
                "Scenario rows before the GIVE valuation year are retained in the copied source inputs for provenance but excluded from the GIVE policy perturbation.",
            "prtp" => PRTP,
            "eta" => ETA,
            "gas" => String(GAS),
            "atmospheric_method" =>
                "direct complete policy methane pathway through GIVE CH4 concentration response and McDuffie reduced-form ozone mortality",
            "momm_atmospheric_response" =>
                "central multi-model mean (MMM)",
            "momm_epidemiological_response" =>
                "central estimate (Inverse.PE)",
            "momm_specific_uncertainty_in_mc" =>
                false,
            "mc_percentile_interpretation" =>
                "p05 and p95 describe dispersion across aligned GIVE socioeconomic and valuation trials; McDuffie-specific epidemiological and atmospheric-model uncertainty is not included",
            "physical_sign" =>
                "positive values are avoided deaths under the regulation pathway",
            "monetary_responses" =>
                ["ISO", "Lancet"],
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
    println(
        "===================================================="
    )
    println(
        "OZONE POLICY PATH RUN COMPLETE"
    )
    println(
        "Mode: ",
        mode
    )
    println(
        "Output: ",
        output_dir
    )
    println(
        "===================================================="
    )
end
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
