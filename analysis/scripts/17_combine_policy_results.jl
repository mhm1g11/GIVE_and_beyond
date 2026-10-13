using DataFrames
using FileIO
using CSVFiles
using Statistics
using JSON
using Dates
include(joinpath(@__DIR__, "config.jl"))
const VALUATION_YEAR = START_YEAR
const OZONE_END_YEAR = 2100
const CLIMATE_END_YEAR = 2300
const CLIMATE_ROOT = joinpath(RELEASE_CONFIG.output_dir, "policy_scenarios")
const OZONE_ROOT = joinpath(RELEASE_CONFIG.output_dir, "policy_ozone")
const COMBINED_ROOT = joinpath(RELEASE_CONFIG.output_dir, "policy_combined")
# ============================================================
# Basic helpers
# ============================================================
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
function expected_trial_count(mode::Symbol)
    mode in (:smoke, :data_smoke) && return 2
    mode == :production && return POLICY_N_TRIALS
    error("Unsupported mode: $mode")
end
function read_csv(path::String)
    isfile(path) || error("Missing required input: $path")
    return DataFrame(load(path))
end
function require_columns(
    table::DataFrame,
    required::Vector{Symbol},
    label::String
)
    missing_cols = setdiff(required, Symbol.(names(table)))
    isempty(missing_cols) ||
        error(
            "$label is missing required columns: " *
            join(string.(missing_cols), ", ")
        )
    return nothing
end
function assert_no_missing(
    table::DataFrame,
    cols::Vector{Symbol},
    label::String
)
    for col in cols
        any(ismissing, table[!, col]) &&
            error("$label contains missing values in column $col")
    end
    return nothing
end
function assert_unique_keys(
    table::DataFrame,
    keys::Vector{Symbol},
    label::String
)
    nrow(table) == nrow(unique(select(table, keys...))) ||
        error(
            "$label contains duplicate rows for keys: " *
            join(string.(keys), ", ")
        )
    return nothing
end
function keyset(
    table::DataFrame,
    keys::Vector{Symbol}
)
    return Set(
        Tuple(row)
        for row in eachrow(select(table, keys...))
    )
end
function assert_same_keys(
    left::DataFrame,
    right::DataFrame,
    keys::Vector{Symbol},
    left_label::String,
    right_label::String
)
    left_keys = keyset(left, keys)
    right_keys = keyset(right, keys)
    left_only = setdiff(left_keys, right_keys)
    right_only = setdiff(right_keys, left_keys)
    if !isempty(left_only) || !isempty(right_only)
        error(
            "Key mismatch between $left_label and $right_label " *
            "for keys $(join(string.(keys), ", ")). " *
            "Rows only in $left_label: $(length(left_only)); " *
            "rows only in $right_label: $(length(right_only))."
        )
    end
    return nothing
end
function assert_expected_scenarios(
    table::DataFrame,
    label::String
)
    scenarios = Set(String.(table.scenario))
    expected = Set(s.name for s in RELEASE_CONFIG.scenarios)
    scenarios == expected ||
        error(
            "$label scenario coverage mismatch. " *
            "Expected $(sort(collect(expected))), " *
            "found $(sort(collect(scenarios)))."
        )
    return nothing
end
function assert_expected_labor_responses(
    table::DataFrame,
    label::String
)
    responses = Set(String.(table.labor_response))
    expected = Set(["ISO", "Lancet"])
    responses == expected ||
        error(
            "$label labor-response coverage mismatch. " *
            "Expected $(sort(collect(expected))), " *
            "found $(sort(collect(responses)))."
        )
    return nothing
end
function assert_trial_design(
    table::DataFrame,
    mode::Symbol,
    label::String;
    include_labor_response::Bool=true
)
    expected_n = expected_trial_count(mode)
    group_keys = include_labor_response ?
        [:scenario, :labor_response] :
        [:scenario]
    for g in groupby(table, group_keys)
        trials = sort(unique(Int.(g.trialnum)))
        length(trials) == expected_n ||
            error(
                "$label has $(length(trials)) unique trials for " *
                "$(NamedTuple(g[1, group_keys])). " *
                "Expected $expected_n."
            )
        trials == collect(1:expected_n) ||
            error(
                "$label trial numbers are not exactly 1:$expected_n for " *
                "$(NamedTuple(g[1, group_keys]))."
            )
        trial_design = unique(
            select(
                g,
                :trialnum,
                :rffsp_id,
                :fair_parameter_set_id,
                :labor_model_id
            )
        )
        nrow(trial_design) == expected_n ||
            error(
                "$label has inconsistent Monte Carlo identifiers within " *
                "trial numbers for $(NamedTuple(g[1, group_keys]))."
            )
    end
    return nothing
end
function assert_iso_lancet_trial_alignment(
    table::DataFrame,
    label::String
)
    keys = [
        :scenario,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :labor_model_id
    ]
    iso = table[table.labor_response .== "ISO", :]
    lancet = table[table.labor_response .== "Lancet", :]
    assert_same_keys(
        iso,
        lancet,
        keys,
        "$label ISO",
        "$label Lancet"
    )
    return nothing
end
function summary_stats(
    table::DataFrame,
    keys::Vector{Symbol},
    value_col::Symbol
)
    rows = DataFrame()
    for g in groupby(table, keys)
        x = Float64.(g[!, value_col])
        all(isfinite, x) ||
            error(
                "Non-finite values encountered in $value_col for " *
                "$(NamedTuple(g[1, keys]))."
            )
        key_values = NamedTuple{Tuple(keys)}(
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
        push!(
            rows,
            merge(key_values, stats);
            cols=:union
        )
    end
    return rows
end
function central_response_means(
    stats::DataFrame,
    group_keys::Vector{Symbol}
)
    rows = DataFrame()
    for g in groupby(stats, group_keys)
        Set(String.(g.labor_response)) == Set(["ISO", "Lancet"]) ||
            error(
                "Both ISO and Lancet are required for central results for " *
                "$(NamedTuple(g[1, group_keys]))."
            )
        nrow(g[g.labor_response .== "ISO", :]) == 1 ||
            error("Expected exactly one ISO summary row.")
        nrow(g[g.labor_response .== "Lancet", :]) == 1 ||
            error("Expected exactly one Lancet summary row.")
        iso = g[g.labor_response .== "ISO", :][1, :]
        lancet = g[g.labor_response .== "Lancet", :][1, :]
        Int(iso.n) == Int(lancet.n) ||
            error(
                "ISO and Lancet trial counts differ for " *
                "$(NamedTuple(g[1, group_keys]))."
            )
        keys = NamedTuple{Tuple(group_keys)}(
            Tuple(g[1, k] for k in group_keys)
        )
        push!(
            rows,
            merge(
                keys,
                (
                    statistic="mean_of_ISO_Lancet_means",
                    mean=(
                        Float64(iso.mean) +
                        Float64(lancet.mean)
                    ) / 2,
                    n_trials_per_response=Int(iso.n)
                )
            );
            cols=:union
        )
    end
    return rows
end
function assert_accounting_identity(
    lhs,
    rhs,
    label::String;
    atol::Float64=1e-6,
    rtol::Float64=1e-10
)
    length(lhs) == length(rhs) ||
        error("$label length mismatch.")
    max_error = maximum(abs.(Float64.(lhs) .- Float64.(rhs)))
    scale = maximum(abs.(Float64.(rhs)))
    tolerance = max(atol, rtol * max(scale, 1.0))
    max_error <= tolerance ||
        error(
            "$label failed. Maximum absolute error = $max_error; " *
            "tolerance = $tolerance."
        )
    return max_error
end
# ============================================================
# Main
# ============================================================
function main()
    mode = parse_mode()
    expected_n = expected_trial_count(mode)
    climate_dir = joinpath(CLIMATE_ROOT, String(mode))
    ozone_dir = joinpath(OZONE_ROOT, String(mode))
    output_dir = joinpath(COMBINED_ROOT, String(mode))
    if isdir(output_dir)
        error("Output already exists; choose a new output_dir: $output_dir")
    end
    mkpath(output_dir)
    println()
    println("====================================================")
    println("COMBINING POLICY RESULTS")
    println("Mode: ", mode)
    println("Expected trials per response: ", expected_n)
    println("====================================================")
    # ========================================================
    # Load source outputs
    # ========================================================
    climate_pv = read_csv(
        joinpath(
            climate_dir,
            "global_monetised_pv_trials.csv"
        )
    )
    temp_pv = read_csv(
        joinpath(
            climate_dir,
            "temperature_mortality_pv_trials_by_response.csv"
        )
    )
    temp_phys = read_csv(
        joinpath(
            climate_dir,
            "temperature_mortality_cumulative_trials.csv"
        )
    )
    temp_annual = read_csv(
        joinpath(
            climate_dir,
            "temperature_mortality_annual_trials.csv"
        )
    )
    ozone_pv = read_csv(
        joinpath(
            ozone_dir,
            "ozone_mortality_pv_trials_by_response.csv"
        )
    )
    ozone_phys = read_csv(
        joinpath(
            ozone_dir,
            "ozone_mortality_cumulative_trials.csv"
        )
    )
    ozone_annual = read_csv(
        joinpath(
            ozone_dir,
            "ozone_mortality_annual_trials.csv"
        )
    )
    # ========================================================
    # Required schemas
    # ========================================================
    id_keys = [
        :scenario,
        :labor_response,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :labor_model_id
    ]
    phys_keys = [
        :scenario,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :labor_model_id,
        :geography
    ]
    annual_keys = [
        :scenario,
        :trialnum,
        :rffsp_id,
        :fair_parameter_set_id,
        :labor_model_id,
        :impact_year,
        :geography
    ]
    require_columns(
        climate_pv,
        [
            id_keys;
            :geography;
            :channel;
            :value_usd2005_pv_valuation_year
        ],
        "climate global monetary PV"
    )
    require_columns(
        temp_pv,
        [
            id_keys;
            :geography;
            :monetised_mortality_usd2005_pv_valuation_year
        ],
        "temperature mortality monetary PV"
    )
    require_columns(
        ozone_pv,
        [
            id_keys;
            :geography;
            :monetised_ozone_mortality_usd2005_pv_valuation_year
        ],
        "ozone mortality monetary PV"
    )
    require_columns(
        temp_phys,
        [
            phys_keys;
            :avoided_deaths
        ],
        "temperature cumulative mortality"
    )
    require_columns(
        ozone_phys,
        [
            phys_keys;
            :avoided_deaths
        ],
        "ozone cumulative mortality"
    )
    require_columns(
        temp_annual,
        [
            annual_keys;
            :avoided_deaths
        ],
        "temperature annual mortality"
    )
    require_columns(
        ozone_annual,
        [
            annual_keys;
            :avoided_deaths
        ],
        "ozone annual mortality"
    )
    # ========================================================
    # General source validation
    # ========================================================
    for (table, label) in (
        (climate_pv, "climate global monetary PV"),
        (temp_pv, "temperature mortality monetary PV"),
        (ozone_pv, "ozone mortality monetary PV")
    )
        assert_no_missing(
            table,
            id_keys,
            label
        )
        assert_expected_scenarios(table, label)
        assert_expected_labor_responses(table, label)
        assert_trial_design(table, mode, label)
        assert_iso_lancet_trial_alignment(table, label)
    end
    for (table, label) in (
        (temp_phys, "temperature cumulative mortality"),
        (ozone_phys, "ozone cumulative mortality"),
        (temp_annual, "temperature annual mortality"),
        (ozone_annual, "ozone annual mortality")
    )
        assert_expected_scenarios(table, label)
        assert_trial_design(
            table,
            mode,
            label;
            include_labor_response=false
        )
    end
    # ========================================================
    # Validate climate channel structure
    # ========================================================
    climate_channel_keys = [
        id_keys;
        :geography;
        :channel
    ]
    assert_unique_keys(
        climate_pv,
        climate_channel_keys,
        "climate global monetary PV"
    )
    climate_geographies = Set(String.(climate_pv.geography))
    climate_geographies == Set(["globe"]) ||
        error(
            "global_monetised_pv_trials.csv must contain only " *
            "geography=globe. Found: " *
            string(sort(collect(climate_geographies)))
        )
    climate_channels_found = Set(String.(climate_pv.channel))
    required_climate_channels = Set([
    "temperature_mortality",
    "agriculture",
    "energy",
    "labor",
    "slr",
    "total_excluding_slr",
    "total_climate"
])
    missing_climate_channels = setdiff(
        required_climate_channels,
        climate_channels_found
    )
    isempty(missing_climate_channels) ||
        error(
            "Climate output is missing required channels: " *
            join(sort(collect(missing_climate_channels)), ", ")
        )
    # ========================================================
    # Validate climate and ozone trial alignment
    # ========================================================
    climate_total_for_alignment = climate_pv[
        climate_pv.channel .== "total_climate",
        :
    ]
    ozone_global_for_alignment = ozone_pv[
        ozone_pv.geography .== "globe",
        :
    ]
    assert_unique_keys(
        climate_total_for_alignment,
        id_keys,
        "climate total"
    )
    assert_unique_keys(
        ozone_global_for_alignment,
        id_keys,
        "global ozone monetary PV"
    )
    assert_same_keys(
        climate_total_for_alignment,
        ozone_global_for_alignment,
        id_keys,
        "climate total",
        "global ozone monetary PV"
    )
    # ========================================================
    # Global channel decomposition
    # ========================================================
    climate_channels = climate_pv[
        .!in.(
            climate_pv.channel,
            Ref([
                "total_excluding_slr",
                "total_climate"
            ])
        ),
        :
    ]
    climate_channels = select(
        climate_channels,
        id_keys...,
        :geography,
        :channel,
        :value_usd2005_pv_valuation_year =>
            :value_usd2005_pv_valuation_year
    )
    ozone_global = ozone_pv[
        ozone_pv.geography .== "globe",
        :
    ]
    ozone_channel = select(
        ozone_global,
        id_keys...,
        :geography,
        :monetised_ozone_mortality_usd2005_pv_valuation_year =>
            :value_usd2005_pv_valuation_year
    )
    ozone_channel.channel = fill(
        "ozone_mortality",
        nrow(ozone_channel)
    )
    global_channels = vcat(
        climate_channels,
        ozone_channel;
        cols=:union
    )
    assert_unique_keys(
        global_channels,
        [
            id_keys;
            :geography;
            :channel
        ],
        "combined global channels"
    )
    sort!(
        global_channels,
        [
            :scenario,
            :labor_response,
            :trialnum,
            :channel
        ]
    )
    save(
        joinpath(
            output_dir,
            "global_channel_pv_trials.csv"
        ),
        global_channels
    )
    # ========================================================
    # Global total societal benefits
    # ========================================================
    climate_total = select(
        climate_total_for_alignment,
        id_keys...,
        :value_usd2005_pv_valuation_year =>
            :climate_usd2005_pv
    )
    ozone_global_total = select(
        ozone_global,
        id_keys...,
        :monetised_ozone_mortality_usd2005_pv_valuation_year =>
            :ozone_usd2005_pv
    )
    global_total = innerjoin(
        climate_total,
        ozone_global_total,
        on=id_keys
    )
    nrow(global_total) == nrow(climate_total) ||
        error(
            "Global climate/ozone join changed row count."
        )
    global_total.total_societal_usd2005_pv =
        global_total.climate_usd2005_pv .+
        global_total.ozone_usd2005_pv
    global_total.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(global_total)
        )
    global_total_accounting_error =
        assert_accounting_identity(
            global_total.total_societal_usd2005_pv,
            global_total.climate_usd2005_pv .+
                global_total.ozone_usd2005_pv,
            "Global societal benefit accounting"
        )
    save(
        joinpath(
            output_dir,
            "global_total_societal_pv_trials.csv"
        ),
        global_total
    )
    global_total_stats = summary_stats(
        global_total,
        [:scenario, :labor_response],
        :total_societal_usd2005_pv
    )
    save(
        joinpath(
            output_dir,
            "global_total_societal_summary_by_response.csv"
        ),
        global_total_stats
    )
    global_total_central = central_response_means(
        global_total_stats,
        [:scenario]
    )
    rename!(
        global_total_central,
        :mean => :total_societal_usd2005_pv
    )
    global_total_central.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(global_total_central)
        )
    save(
        joinpath(
            output_dir,
            "global_total_societal_central_means.csv"
        ),
        global_total_central
    )
    global_channel_stats = summary_stats(
        global_channels,
        [
            :scenario,
            :labor_response,
            :channel
        ],
        :value_usd2005_pv_valuation_year
    )
    save(
        joinpath(
            output_dir,
            "global_channel_summary_by_response.csv"
        ),
        global_channel_stats
    )
    global_channel_central = central_response_means(
        global_channel_stats,
        [:scenario, :channel]
    )
    rename!(
        global_channel_central,
        :mean =>
            :value_usd2005_pv_valuation_year
    )
    global_channel_central.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(global_channel_central)
        )
    save(
        joinpath(
            output_dir,
            "global_channel_central_means.csv"
        ),
        global_channel_central
    )
    # ========================================================
    # Regional mortality monetary benefits
    # ========================================================
    mortality_money_keys = [
        id_keys;
        :geography
    ]
    assert_unique_keys(
        temp_pv,
        mortality_money_keys,
        "temperature mortality monetary PV"
    )
    assert_unique_keys(
        ozone_pv,
        mortality_money_keys,
        "ozone mortality monetary PV"
    )
    assert_same_keys(
        temp_pv,
        ozone_pv,
        mortality_money_keys,
        "temperature mortality monetary PV",
        "ozone mortality monetary PV"
    )
    temp_mort = select(
        temp_pv,
        id_keys...,
        :geography,
        :monetised_mortality_usd2005_pv_valuation_year =>
            :temperature_mortality_usd2005_pv
    )
    ozone_mort = select(
        ozone_pv,
        id_keys...,
        :geography,
        :monetised_ozone_mortality_usd2005_pv_valuation_year =>
            :ozone_mortality_usd2005_pv
    )
    mortality_total = innerjoin(
        temp_mort,
        ozone_mort,
        on=mortality_money_keys
    )
    nrow(mortality_total) == nrow(temp_mort) ||
        error(
            "Temperature/ozone mortality monetary join " *
            "changed row count."
        )
    mortality_total.total_mortality_usd2005_pv =
        mortality_total.temperature_mortality_usd2005_pv .+
        mortality_total.ozone_mortality_usd2005_pv
    mortality_total.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(mortality_total)
        )
    mortality_money_accounting_error =
        assert_accounting_identity(
            mortality_total.total_mortality_usd2005_pv,
            mortality_total.temperature_mortality_usd2005_pv .+
                mortality_total.ozone_mortality_usd2005_pv,
            "Monetised mortality accounting"
        )
    save(
        joinpath(
            output_dir,
            "mortality_monetised_pv_trials.csv"
        ),
        mortality_total
    )
    mortality_component_trials = DataFrame()
    for row in eachrow(mortality_total)
        identity = (
            scenario=String(row.scenario),
            labor_response=String(row.labor_response),
            trialnum=Int(row.trialnum),
            rffsp_id=Int(row.rffsp_id),
            fair_parameter_set_id=
                Int(row.fair_parameter_set_id),
            labor_model_id=Int(row.labor_model_id),
            geography=String(row.geography)
        )
        for (channel, value) in (
            (
                "temperature_mortality",
                Float64(
                    row.temperature_mortality_usd2005_pv
                )
            ),
            (
                "ozone_mortality",
                Float64(
                    row.ozone_mortality_usd2005_pv
                )
            ),
            (
                "total_mortality",
                Float64(
                    row.total_mortality_usd2005_pv
                )
            )
        )
            push!(
                mortality_component_trials,
                merge(
                    identity,
                    (
                        channel=channel,
                        value_usd2005_pv=value
                    )
                );
                cols=:union
            )
        end
    end
    save(
        joinpath(
            output_dir,
            "mortality_monetised_channel_pv_trials.csv"
        ),
        mortality_component_trials
    )
    mortality_component_stats = summary_stats(
        mortality_component_trials,
        [
            :scenario,
            :labor_response,
            :geography,
            :channel
        ],
        :value_usd2005_pv
    )
    save(
        joinpath(
            output_dir,
            "mortality_monetised_channel_summary_by_response.csv"
        ),
        mortality_component_stats
    )
    mortality_component_central =
        central_response_means(
            mortality_component_stats,
            [
                :scenario,
                :geography,
                :channel
            ]
        )
    rename!(
        mortality_component_central,
        :mean => :value_usd2005_pv
    )
    mortality_component_central.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(mortality_component_central)
        )
    save(
        joinpath(
            output_dir,
            "mortality_monetised_channel_central_means.csv"
        ),
        mortality_component_central
    )
    mortality_money_stats = summary_stats(
        mortality_total,
        [
            :scenario,
            :labor_response,
            :geography
        ],
        :total_mortality_usd2005_pv
    )
    save(
        joinpath(
            output_dir,
            "mortality_monetised_summary_by_response.csv"
        ),
        mortality_money_stats
    )
    mortality_money_central =
        central_response_means(
            mortality_money_stats,
            [
                :scenario,
                :geography
            ]
        )
    rename!(
        mortality_money_central,
        :mean =>
            :total_mortality_usd2005_pv
    )
    mortality_money_central.valuation_year =
        fill(
            VALUATION_YEAR,
            nrow(mortality_money_central)
        )
    save(
        joinpath(
            output_dir,
            "mortality_monetised_central_means.csv"
        ),
        mortality_money_central
    )
    # ========================================================
    # Physical cumulative avoided deaths
    # ========================================================
    assert_unique_keys(
        temp_phys,
        phys_keys,
        "temperature cumulative mortality"
    )
    assert_unique_keys(
        ozone_phys,
        phys_keys,
        "ozone cumulative mortality"
    )
    assert_same_keys(
        temp_phys,
        ozone_phys,
        phys_keys,
        "temperature cumulative mortality",
        "ozone cumulative mortality"
    )
    temp_phys2 = select(
        temp_phys,
        phys_keys...,
        :avoided_deaths =>
            :temperature_avoided_deaths
    )
    ozone_phys2 = select(
        ozone_phys,
        phys_keys...,
        :avoided_deaths =>
            :ozone_avoided_deaths
    )
    physical_total = innerjoin(
        temp_phys2,
        ozone_phys2,
        on=phys_keys
    )
    nrow(physical_total) == nrow(temp_phys2) ||
        error(
            "Temperature/ozone cumulative mortality join " *
            "changed row count."
        )
    physical_total.total_avoided_deaths =
        physical_total.temperature_avoided_deaths .+
        physical_total.ozone_avoided_deaths
    physical_accounting_error =
        assert_accounting_identity(
            physical_total.total_avoided_deaths,
            physical_total.temperature_avoided_deaths .+
                physical_total.ozone_avoided_deaths,
            "Cumulative physical mortality accounting"
        )
    save(
        joinpath(
            output_dir,
            "mortality_physical_cumulative_trials.csv"
        ),
        physical_total
    )
    physical_component_trials = DataFrame()
    for row in eachrow(physical_total)
        identity = (
            scenario=String(row.scenario),
            trialnum=Int(row.trialnum),
            rffsp_id=Int(row.rffsp_id),
            fair_parameter_set_id=
                Int(row.fair_parameter_set_id),
            labor_model_id=Int(row.labor_model_id),
            geography=String(row.geography)
        )
        for (channel, value) in (
            (
                "temperature_mortality",
                Float64(
                    row.temperature_avoided_deaths
                )
            ),
            (
                "ozone_mortality",
                Float64(
                    row.ozone_avoided_deaths
                )
            ),
            (
                "total_mortality",
                Float64(
                    row.total_avoided_deaths
                )
            )
        )
            push!(
                physical_component_trials,
                merge(
                    identity,
                    (
                        channel=channel,
                        avoided_deaths=value
                    )
                );
                cols=:union
            )
        end
    end
    save(
        joinpath(
            output_dir,
            "mortality_physical_channel_trials.csv"
        ),
        physical_component_trials
    )
    physical_component_stats = summary_stats(
        physical_component_trials,
        [
            :scenario,
            :geography,
            :channel
        ],
        :avoided_deaths
    )
    save(
        joinpath(
            output_dir,
            "mortality_physical_channel_summary.csv"
        ),
        physical_component_stats
    )
    # ========================================================
    # Annual physical mortality
    #
    # Temperature mortality runs through 2300.
    # Ozone mortality runs through 2100.
    #
    # Missing ozone observations are converted to zero ONLY
    # after 2100. Missing observations inside the ozone
    # horizon are treated as an error.
    # ========================================================
    assert_unique_keys(
        temp_annual,
        annual_keys,
        "temperature annual mortality"
    )
    assert_unique_keys(
        ozone_annual,
        annual_keys,
        "ozone annual mortality"
    )
    temp_year_min = minimum(Int.(temp_annual.impact_year))
    temp_year_max = maximum(Int.(temp_annual.impact_year))
    ozone_year_min = minimum(Int.(ozone_annual.impact_year))
    ozone_year_max = maximum(Int.(ozone_annual.impact_year))
    temp_year_min == VALUATION_YEAR ||
        error(
            "Temperature annual mortality starts in " *
            "$temp_year_min; expected $VALUATION_YEAR."
        )
    temp_year_max == CLIMATE_END_YEAR ||
        error(
            "Temperature annual mortality ends in " *
            "$temp_year_max; expected $CLIMATE_END_YEAR."
        )
    ozone_year_min == VALUATION_YEAR ||
        error(
            "Ozone annual mortality starts in " *
            "$ozone_year_min; expected $VALUATION_YEAR."
        )
    ozone_year_max == OZONE_END_YEAR ||
        error(
            "Ozone annual mortality ends in " *
            "$ozone_year_max; expected $OZONE_END_YEAR."
        )
    temp_overlap = temp_annual[
        temp_annual.impact_year .<= OZONE_END_YEAR,
        :
    ]
    assert_same_keys(
        temp_overlap,
        ozone_annual,
        annual_keys,
        "temperature annual mortality through 2100",
        "ozone annual mortality"
    )
    temp_annual2 = select(
        temp_annual,
        annual_keys...,
        :avoided_deaths =>
            :temperature_avoided_deaths
    )
    ozone_annual2 = select(
        ozone_annual,
        annual_keys...,
        :avoided_deaths =>
            :ozone_avoided_deaths
    )
    mortality_annual = leftjoin(
        temp_annual2,
        ozone_annual2,
        on=annual_keys
    )
    nrow(mortality_annual) == nrow(temp_annual2) ||
        error(
            "Annual mortality join changed temperature row count."
        )
    missing_ozone_inside_horizon =
        ismissing.(mortality_annual.ozone_avoided_deaths) .&
        (mortality_annual.impact_year .<= OZONE_END_YEAR)
    any(missing_ozone_inside_horizon) &&
        error(
            "Missing ozone annual mortality observations " *
            "within the configured valuation-year to 2100 ozone horizon."
        )
    missing_ozone_after_horizon =
        ismissing.(mortality_annual.ozone_avoided_deaths) .&
        (mortality_annual.impact_year .> OZONE_END_YEAR)
    expected_missing_after_horizon =
        mortality_annual.impact_year .> OZONE_END_YEAR
    all(
        missing_ozone_after_horizon .==
        expected_missing_after_horizon
    ) ||
        error(
            "Unexpected ozone observations after 2100 or " *
            "unexpected missingness pattern."
        )
    mortality_annual.ozone_avoided_deaths =
        coalesce.(
            mortality_annual.ozone_avoided_deaths,
            0.0
        )
    any(
        ismissing,
        mortality_annual.temperature_avoided_deaths
    ) &&
        error(
            "Temperature annual mortality contains missing values."
        )
    mortality_annual.total_avoided_deaths =
        mortality_annual.temperature_avoided_deaths .+
        mortality_annual.ozone_avoided_deaths
    annual_accounting_error =
        assert_accounting_identity(
            mortality_annual.total_avoided_deaths,
            mortality_annual.temperature_avoided_deaths .+
                mortality_annual.ozone_avoided_deaths,
            "Annual physical mortality accounting"
        )
    sort!(
        mortality_annual,
        [
            :scenario,
            :trialnum,
            :geography,
            :impact_year
        ]
    )
    save(
        joinpath(
            output_dir,
            "mortality_physical_annual_trials.csv"
        ),
        mortality_annual
    )
    physical_stats = summary_stats(
        physical_total,
        [
            :scenario,
            :geography
        ],
        :total_avoided_deaths
    )
    save(
        joinpath(
            output_dir,
            "mortality_physical_summary.csv"
        ),
        physical_stats
    )
    # ========================================================
    # Compact final central table
    # ========================================================
    final = DataFrame(
        scenario=String[],
        geography=String[],
        metric=String[],
        channel=String[],
        value=Float64[],
        unit=String[],
        valuation_year=Union{Missing,Int}[]
    )
    for row in eachrow(global_channel_central)
        push!(
            final,
            (
                scenario=String(row.scenario),
                geography="globe",
                metric="monetised_benefit",
                channel=String(row.channel),
                value=Float64(
                    row.value_usd2005_pv_valuation_year
                ),
                unit="USD2005_PV",
                valuation_year=VALUATION_YEAR
            )
        )
    end
    for row in eachrow(global_total_central)
        push!(
            final,
            (
                scenario=String(row.scenario),
                geography="globe",
                metric="monetised_benefit",
                channel="total_societal",
                value=Float64(
                    row.total_societal_usd2005_pv
                ),
                unit="USD2005_PV",
                valuation_year=VALUATION_YEAR
            )
        )
    end
    for row in eachrow(mortality_component_central)
        if String(row.geography) == "globe" &&
           String(row.channel) != "total_mortality"
            continue
        end
        push!(
            final,
            (
                scenario=String(row.scenario),
                geography=String(row.geography),
                metric="monetised_benefit",
                channel=String(row.channel),
                value=Float64(
                    row.value_usd2005_pv
                ),
                unit="USD2005_PV",
                valuation_year=VALUATION_YEAR
            )
        )
    end
    for row in eachrow(physical_component_stats)
        push!(
            final,
            (
                scenario=String(row.scenario),
                geography=String(row.geography),
                metric="physical_impact",
                channel=String(row.channel),
                value=Float64(row.mean),
                unit="deaths",
                valuation_year=missing
            )
        )
    end
    assert_unique_keys(
        final,
        [
            :scenario,
            :geography,
            :metric,
            :channel
        ],
        "final central results"
    )
    sort!(
        final,
        [
            :scenario,
            :geography,
            :metric,
            :channel
        ]
    )
    save(
        joinpath(
            output_dir,
            "final_central_results.csv"
        ),
        final
    )
    # ========================================================
    # Final validation metadata
    # ========================================================
    metadata = Dict(
        "status" => "PASS",
        "mode" => String(mode),
        "expected_trials_per_response" => expected_n,
        "valuation_year" => VALUATION_YEAR,
        "climate_horizon_end" => CLIMATE_END_YEAR,
        "ozone_horizon_end" => OZONE_END_YEAR,
        "global_total" =>
            "GIVE climate total including labour productivity and sea-level rise, plus ozone respiratory mortality",
        "global_climate_channels" =>
            sort(collect(required_climate_channels)),
        "regional_scope" =>
            "EU27 and DEU report temperature and ozone mortality only",
        "physical_mortality" =>
            "temperature-related avoided deaths plus ozone respiratory avoided deaths",
        "annual_ozone_after_2100" =>
            "set to zero only after validation that the complete configured ozone horizon is present",
        "central_monetary_definition" =>
            "arithmetic mean of ISO and Lancet formulation means",
        "global_total_accounting_max_abs_error" =>
            global_total_accounting_error,
        "mortality_monetary_accounting_max_abs_error" =>
            mortality_money_accounting_error,
        "mortality_cumulative_physical_accounting_max_abs_error" =>
            physical_accounting_error,
        "mortality_annual_physical_accounting_max_abs_error" =>
            annual_accounting_error,
        "created" => string(now())
    )
    open(
        joinpath(output_dir, "validation.json"),
        "w"
    ) do io
        JSON.print(io, metadata, 2)
    end
    println()
    println("====================================================")
    println("COMBINED POLICY RESULTS COMPLETE")
    println("Mode: ", mode)
    println("Trials per response: ", expected_n)
    println("Climate horizon: ", VALUATION_YEAR, "-", CLIMATE_END_YEAR)
    println("Ozone horizon: ", VALUATION_YEAR, "-", OZONE_END_YEAR)
    println("Validation: PASS")
    println("Output: ", output_dir)
    println("====================================================")
end
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
