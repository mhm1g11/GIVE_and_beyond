"""
Build the 2024 reduced-form global monetary CH4 damage factor for GLLEX.

This script RUNS MimiGIVE Monte Carlo calculations.

It calculates:

    1. Global GIVE climate damages from a 2024 CH4 pulse
    2. Global methane-induced ozone mortality damages
    3. Extended global CH4 damages:

           GIVE climate damages
           + ozone mortality damages

Only 2024 is calculated because the existing external CH4 factor library
already contains 2025.

Only global monetary damages are retained.

The ozone methodology is identical to the existing GIVE-first
McDuffie implementation, but this external script deliberately avoids:

    country-level output files
    EU27 aggregation
    Germany aggregation
    physical mortality output
    multiple pulse years

Outputs:

    research/outputs/reduced_form_ch4_2024_damage_factors_trials.csv
    research/outputs/reduced_form_ch4_2024_damage_factors_summary.csv

Headline GLLEX metric:

    extended_total_monetised

Monetary values are exported in:

    USD2005 per tonne CH4
    USD2026 per tonne CH4

The intended interpretation is:

    expected discounted global societal damage
    per tonne CH4 emitted in 2024
"""

using Random
using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics


# =====================================================================
# Project modules and configuration
# =====================================================================

include(
    joinpath(
        @__DIR__,
        "..",
        "src",
        "MethaneOzoneMortality.jl"
    )
)

using .MethaneOzoneMortality

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)


# =====================================================================
# External calculation settings
# =====================================================================

const PULSE_YEAR = 2024
const EXTERNAL_GAS = :CH4
const TARGET_GEOGRAPHY = "globe"

const MC_SEED = 20260908


# =====================================================================
# Current-dollar conversion
# =====================================================================

const CPI_2005_ANNUAL_AVERAGE =
    195.3

const CPI_2026_CURRENT =
    334.980

const CPI_UPRATING_FACTOR =
    CPI_2026_CURRENT /
    CPI_2005_ANNUAL_AVERAGE

const ORIGINAL_UNIT =
    "USD2005_per_t_CH4"

const CURRENT_UNIT =
    "USD2026_per_t_CH4"

const PRICE_BASIS =
    "August 2026 CPI-U, U.S. city average, all items"

const CPI_SOURCE =
    "U.S. Bureau of Labor Statistics"


# =====================================================================
# Paths
# =====================================================================

const MOMM_ROOT = normpath(
    joinpath(
        @__DIR__,
        "..",
        "external",
        "MOMM-RFT"
    )
)

const TRIAL_DESIGN_PATH = joinpath(
    INPUT_DIR,
    "mc_trial_design.csv"
)

const MOMM_SOCIO_PATH = joinpath(
    OUTPUT_DIR,
    "momm_reference_socioeconomics.csv"
)

const CLIMATE_RUN_DIR = joinpath(
    GIVE_RUN_DIR,
    "external_ch4_2024_climate"
)

const OZONE_MCS_OUTPUT_DIR = joinpath(
    OUTPUT_DIR,
    "external_ch4_2024_ozone_mcs"
)

const TRIAL_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_ch4_2024_damage_factors_trials.csv"
)

const SUMMARY_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "reduced_form_ch4_2024_damage_factors_summary.csv"
)

mkpath(
    OUTPUT_DIR
)

mkpath(
    GIVE_RUN_DIR
)


# =====================================================================
# Helpers
# =====================================================================

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


function as_float_or_missing(x)

    if ismissing(x)
        return missing
    end

    if x isa Real

        value =
            Float64(x)

        return isfinite(value) ?
            value :
            missing
    end

    value =
        strip(
            string(x)
        )

    if isempty(value)
        return missing
    end

    if lowercase(value) in [
        "missing",
        "na",
        "n/a",
        "nan"
    ]
        return missing
    end

    parsed =
        parse(
            Float64,
            value
        )

    return isfinite(parsed) ?
        parsed :
        missing
end


function find_column(
    df::DataFrame,
    candidates::Vector{Symbol}
)

    available =
        propertynames(df)

    for candidate in candidates

        if candidate in available
            return candidate
        end
    end

    error(
        "Could not find any of $(candidates). " *
        "Available columns are $(available)."
    )
end


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

    all(
        isfinite,
        values
    ) ||
        error(
            "Non-finite SCC values found for sector $sector."
        )

    return values
end


function clean_country_variable(
    df::DataFrame,
    value_candidates::Vector{Symbol},
    output_value::Symbol
)

    trial_col =
        find_column(
            df,
            [
                :trialnum,
                :trial,
                :trial_number
            ]
        )

    time_col =
        find_column(
            df,
            [
                :time,
                :year
            ]
        )

    country_col =
        find_column(
            df,
            [
                :country,
                :countries
            ]
        )

    value_col =
        find_column(
            df,
            value_candidates
        )

    clean = select(
        df,

        trial_col =>
            :trialnum,

        time_col =>
            :year,

        country_col =>
            :iso3,

        value_col =>
            output_value
    )

    clean.trialnum =
        as_int.(
            clean.trialnum
        )

    clean.year =
        as_int.(
            clean.year
        )

    clean.iso3 = [
        ismissing(x) ?
            "" :
            strip(
                string(x)
            )
        for x in clean.iso3
    ]

    clean[
        !,
        output_value
    ] =
        as_float_or_missing.(
            clean[
                !,
                output_value
            ]
        )

    return clean
end


function make_factor_rows(
    trial_design::DataFrame,
    metric::String,
    values,
    source::String
)

    n =
        nrow(
            trial_design
        )

    length(values) ==
        n ||
        error(
            "Expected $n values for $metric, " *
            "found $(length(values))."
        )

    values_2005 =
        Float64.(
            values
        )

    values_2026 =
        values_2005 .*
        CPI_UPRATING_FACTOR

    return DataFrame(
        gas =
            fill(
                "CH4",
                n
            ),

        pulse_year =
            fill(
                PULSE_YEAR,
                n
            ),

        trialnum =
            Int.(
                trial_design.trialnum
            ),

        rffsp_id =
            Int.(
                trial_design.rffsp_id
            ),

        fair_parameter_set_id =
            Int.(
                trial_design.fair_parameter_set_id
            ),

        geography =
            fill(
                TARGET_GEOGRAPHY,
                n
            ),

        metric =
            fill(
                metric,
                n
            ),

        value_usd2005_per_t_ch4 =
            values_2005,

        value_usd2026_per_t_ch4 =
            values_2026,

        original_unit =
            fill(
                ORIGINAL_UNIT,
                n
            ),

        current_unit =
            fill(
                CURRENT_UNIT,
                n
            ),

        source =
            fill(
                source,
                n
            )
    )
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

        value_usd2005_per_t_ch4 =
            Float64[],

        value_usd2026_per_t_ch4 =
            Float64[],

        original_unit = String[],
        current_unit = String[],
        source = String[],

        n_trials = Int[],

        cpi_u_2005 = Float64[],
        cpi_u_2026 = Float64[],
        cpi_uprating_factor = Float64[],

        price_basis = String[],
        cpi_source = String[]
    )

    for group in groupby(
        df,
        [
            :gas,
            :pulse_year,
            :geography,
            :metric,
            :source
        ]
    )

        values =
            Float64.(
                group.value_usd2005_per_t_ch4
            )

        stats = [
            (
                "mean",
                mean(values)
            ),
            (
                "median",
                median(values)
            ),
            (
                "p05",
                quantile(
                    values,
                    0.05
                )
            ),
            (
                "p95",
                quantile(
                    values,
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

                    String(
                        group.source[1]
                    ),

                    length(values),

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
            :metric,
            :statistic
        ]
    )

    return result
end


# =====================================================================
# 1. Load explicit Monte Carlo trial design
# =====================================================================

trial_design =
    DataFrame(
        load(
            TRIAL_DESIGN_PATH
        )
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

sort!(
    trial_design,
    :trialnum
)

const N_TRIALS =
    nrow(
        trial_design
    )

N_TRIALS > 0 ||
    error(
        "mc_trial_design.csv must contain at least one trial."
    )

trial_design.trialnum ==
    collect(
        1:N_TRIALS
    ) ||
    error(
        "mc_trial_design.csv must contain consecutive trial numbers 1:N."
    )

const RFFSP_IDS =
    collect(
        trial_design.rffsp_id
    )

const FAIR_IDS =
    collect(
        trial_design.fair_parameter_set_id
    )


# =====================================================================
# Console header
# =====================================================================

println()
println(
    "BUILDING 2024 GLOBAL CH4 DAMAGE FACTOR FOR GLLEX"
)

println(
    "================================================"
)

println()

println(
    "Pulse year:          ",
    PULSE_YEAR
)

println(
    "Gas:                 ",
    EXTERNAL_GAS
)

println(
    "Geography:           ",
    TARGET_GEOGRAPHY
)

println(
    "Impact horizon:      ",
    IMPACT_HORIZON
)

println(
    "Trials:              ",
    N_TRIALS
)

println(
    "Monte Carlo seed:    ",
    MC_SEED
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


# =====================================================================
# 2. Run global GIVE climate-damage calculation
# =====================================================================

println(
    "STEP 1: Running global GIVE CH4 climate-damage calculation..."
)

if isdir(
    CLIMATE_RUN_DIR
)

    rm(
        CLIMATE_RUN_DIR;
        recursive = true,
        force = true
    )
end

Random.seed!(
    MC_SEED
)

climate_result =
    MimiGIVE.compute_scc(
        year =
            PULSE_YEAR,

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
            CLIMATE_RUN_DIR
    )

give_climate_total =
    official_global_scc(
        climate_result,
        :total
    )

length(
    give_climate_total
) ==
    N_TRIALS ||
    error(
        "Incorrect number of global GIVE climate-damage trials."
    )

println(
    "GIVE climate calculation complete."
)

println(
    "Mean GIVE climate damage: ",
    round(
        mean(
            give_climate_total
        ),
        digits = 3
    ),
    " USD2005/t CH4"
)

println()


# =====================================================================
# 3. Load McDuffie socioeconomic reference denominators
# =====================================================================

momm_socio =
    DataFrame(
        load(
            MOMM_SOCIO_PATH
        )
    )

momm_socio.year =
    as_int.(
        momm_socio.year
    )

momm_socio.reference_population_thousands =
    as_float_or_missing.(
        momm_socio.reference_population_thousands
    )

momm_socio.reference_allcause_mortality_rate =
    as_float_or_missing.(
        momm_socio.reference_allcause_mortality_rate
    )

momm_socio.iso3_clean = [
    ismissing(x) ?
        "" :
        strip(
            string(x)
        )
    for x in momm_socio.iso3
]

momm_valid =
    filter(
        row ->
            !isempty(
                row.iso3_clean
            ),
        momm_socio
    )

duplicates =
    combine(
        groupby(
            momm_valid,
            [
                :iso3_clean,
                :year
            ]
        ),
        nrow =>
            :n
    )

duplicates =
    filter(
        row ->
            row.n > 1,
        duplicates
    )

nrow(
    duplicates
) ==
    0 ||
    error(
        "Duplicate mapped McDuffie ISO3/year rows found."
    )


# =====================================================================
# 4. Run GIVE MCS for ozone socioeconomic and valuation inputs
# =====================================================================

println(
    "STEP 2: Running GIVE MCS for ozone socioeconomic and VSL inputs..."
)

if isdir(
    OZONE_MCS_OUTPUT_DIR
)

    rm(
        OZONE_MCS_OUTPUT_DIR;
        recursive = true,
        force = true
    )
end

m =
    MimiGIVE.get_model()

Random.seed!(
    MC_SEED
)

mcs =
    MimiGIVE.run_mcs(
        trials =
            N_TRIALS,

        m =
            m,

        fair_parameter_set =
            :deterministic,

        fair_parameter_set_ids =
            FAIR_IDS,

        rffsp_sampling =
            :deterministic,

        rffsp_sampling_ids =
            RFFSP_IDS,

        save_list = [
            (
                :Socioeconomic,
                :population
            ),
            (
                :Socioeconomic,
                :deathrate
            ),
            (
                :VSL,
                :vsl
            ),
            (
                :global_netconsumption,
                :net_cpc
            )
        ],

        output_dir =
            OZONE_MCS_OUTPUT_DIR,

        results_in_memory =
            true
    )

println(
    "GIVE ozone-input MCS complete."
)

println()


# =====================================================================
# 5. Extract trial-specific GIVE variables
# =====================================================================

population_raw =
    getdataframe(
        mcs,
        :Socioeconomic,
        :population
    )

deathrate_raw =
    getdataframe(
        mcs,
        :Socioeconomic,
        :deathrate
    )

vsl_raw =
    getdataframe(
        mcs,
        :VSL,
        :vsl
    )

cpc_raw =
    getdataframe(
        mcs,
        :global_netconsumption,
        :net_cpc
    )


population =
    clean_country_variable(
        population_raw,
        [
            :population
        ],
        :give_population_millions
    )

deathrate =
    clean_country_variable(
        deathrate_raw,
        [
            :deathrate
        ],
        :give_deathrate_per_thousand
    )

vsl =
    clean_country_variable(
        vsl_raw,
        [
            :vsl
        ],
        :give_vsl_usd2005
    )


trial_col_cpc =
    find_column(
        cpc_raw,
        [
            :trialnum,
            :trial,
            :trial_number
        ]
    )

time_col_cpc =
    find_column(
        cpc_raw,
        [
            :time,
            :year
        ]
    )

value_col_cpc =
    find_column(
        cpc_raw,
        [
            :net_cpc
        ]
    )

cpc =
    select(
        cpc_raw,

        trial_col_cpc =>
            :trialnum,

        time_col_cpc =>
            :year,

        value_col_cpc =>
            :global_net_cpc
    )

cpc.trialnum =
    as_int.(
        cpc.trialnum
    )

cpc.year =
    as_int.(
        cpc.year
    )

cpc.global_net_cpc =
    as_float_or_missing.(
        cpc.global_net_cpc
    )


population =
    filter(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        population
    )

deathrate =
    filter(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        deathrate
    )

vsl =
    filter(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        vsl
    )

cpc =
    filter(
        row ->
            2020 <=
            row.year <=
            IMPACT_HORIZON,
        cpc
    )


# =====================================================================
# 6. Merge GIVE socioeconomic inputs
# =====================================================================

give_socio =
    leftjoin(
        population,
        deathrate,
        on = [
            :trialnum,
            :year,
            :iso3
        ]
    )

give_socio =
    leftjoin(
        give_socio,
        vsl,
        on = [
            :trialnum,
            :year,
            :iso3
        ]
    )


momm_join =
    select(
        momm_valid,

        :iso3_clean =>
            :iso3,

        :year,

        :reference_population_thousands,

        :reference_allcause_mortality_rate
    )

trial_socio =
    leftjoin(
        give_socio,
        momm_join,
        on = [
            :iso3,
            :year
        ]
    )


trial_socio.socioeconomic_scale =
    Vector{Float64}(
        undef,
        nrow(
            trial_socio
        )
    )

trial_socio.give_socio_match =
    Vector{Bool}(
        undef,
        nrow(
            trial_socio
        )
    )


for (
    i,
    row
) in enumerate(
    eachrow(
        trial_socio
    )
)

    pop_ok =
        !ismissing(
            row.give_population_millions
        ) &&
        !ismissing(
            row.reference_population_thousands
        ) &&
        row.reference_population_thousands >
        0

    mort_ok =
        !ismissing(
            row.give_deathrate_per_thousand
        ) &&
        !ismissing(
            row.reference_allcause_mortality_rate
        ) &&
        row.reference_allcause_mortality_rate >
        0


    if pop_ok &&
       mort_ok

        momm_population_millions =
            Float64(
                row.reference_population_thousands
            ) /
            1000

        give_mortality_rate =
            Float64(
                row.give_deathrate_per_thousand
            ) /
            1000

        population_scale =
            Float64(
                row.give_population_millions
            ) /
            momm_population_millions

        mortality_scale =
            give_mortality_rate /
            Float64(
                row.reference_allcause_mortality_rate
            )

        trial_socio.socioeconomic_scale[
            i
        ] =
            population_scale *
            mortality_scale

        trial_socio.give_socio_match[
            i
        ] =
            true

    else

        trial_socio.socioeconomic_scale[
            i
        ] =
            1.0

        trial_socio.give_socio_match[
            i
        ] =
            false
    end
end


# =====================================================================
# 7. Build socioeconomic and consumption lookups
# =====================================================================

socio_lookup =
    Dict{
        Tuple{Int, String, Int},
        NamedTuple
    }()


for row in eachrow(
    trial_socio
)

    key = (
        Int(
            row.trialnum
        ),
        string(
            row.iso3
        ),
        Int(
            row.year
        )
    )

    socio_lookup[
        key
    ] = (
        socioeconomic_scale =
            Float64(
                row.socioeconomic_scale
            ),

        give_socio_match =
            Bool(
                row.give_socio_match
            ),

        give_vsl_usd2005 =
            row.give_vsl_usd2005
    )
end


cpc_lookup =
    Dict{
        Tuple{Int, Int},
        Float64
    }()


for row in eachrow(
    cpc
)

    if !ismissing(
        row.global_net_cpc
    )

        cpc_lookup[
            (
                Int(
                    row.trialnum
                ),
                Int(
                    row.year
                )
            )
        ] =
            Float64(
                row.global_net_cpc
            )
    end
end


function give_trial_discount_factor(
    trialnum::Int,
    impact_year::Int
)

    impact_year <
        PULSE_YEAR &&
        return 0.0

    pulse_key = (
        trialnum,
        PULSE_YEAR
    )

    impact_key = (
        trialnum,
        impact_year
    )

    haskey(
        cpc_lookup,
        pulse_key
    ) ||
        error(
            "Missing GIVE global net CPC for trial " *
            "$trialnum, year $PULSE_YEAR."
        )

    haskey(
        cpc_lookup,
        impact_key
    ) ||
        error(
            "Missing GIVE global net CPC for trial " *
            "$trialnum, year $impact_year."
        )

    cpc_pulse =
        cpc_lookup[
            pulse_key
        ]

    cpc_impact =
        cpc_lookup[
            impact_key
        ]

    return (
        (
            cpc_pulse /
            cpc_impact
        )^ETA
        /
        (
            1 +
            PRTP
        )^(
            impact_year -
            PULSE_YEAR
        )
    )
end


# =====================================================================
# 8. Build deterministic 2024 atmospheric ozone response
# =====================================================================

println(
    "STEP 3: Building 2024 methane-induced ozone response..."
)

reference =
    load_momm_reference(
        MOMM_ROOT
    )

m_det =
    MimiGIVE.get_model()

mm =
    MimiGIVE.get_marginal_model(
        m_det;
        year =
            PULSE_YEAR,
        gas =
            :CH4,
        pulse_size =
            PULSE_SIZE_MT
    )

run(
    mm
)

give_years =
    collect(
        dim_keys(
            mm.base,
            :time
        )
    )

delta_ch4 =
    mm.modified[
        :ch4_cycle,
        :CH₄
    ] .-
    mm.base[
        :ch4_cycle,
        :CH₄
    ]

years =
    collect(
        2020:
        IMPACT_HORIZON
    )

indices = [
    findfirst(
        ==(year),
        give_years
    )
    for year in years
]

any(
    isnothing,
    indices
) &&
    error(
        "Required year missing from GIVE."
    )

give_delta = [
    Float64(
        delta_ch4[
            idx
        ]
    )
    for idx in indices
]

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
        strip(
            string(x)
        )
    for x in atmosphere.iso3
]

atmosphere =
    filter(
        row ->
            PULSE_YEAR <=
            row.year <=
            IMPACT_HORIZON,
        atmosphere
    )

println(
    "Atmospheric ozone response complete."
)

println()


# =====================================================================
# 9. Trial-specific global ozone valuation
#
# No country-level rows are retained.
# =====================================================================

println(
    "STEP 4: Valuing global ozone mortality across aligned trials..."
)

ozone_monetary =
    zeros(
        N_TRIALS
    )

socio_coverage =
    zeros(
        N_TRIALS
    )

vsl_coverage =
    zeros(
        N_TRIALS
    )


for trial in eachrow(
    trial_design
)

    trialnum =
        Int(
            trial.trialnum
        )

    monetary_value =
        0.0

    physical_deaths =
        0.0

    socio_matched_deaths =
        0.0

    valued_deaths =
        0.0


    for row in eachrow(
        atmosphere
    )

        impact_year =
            Int(
                row.year
            )

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


        if !isempty(
            iso3
        ) &&
           haskey(
               socio_lookup,
               key
           )

            inputs =
                socio_lookup[
                    key
                ]

            socioeconomic_scale =
                inputs.socioeconomic_scale

            give_socio_match =
                inputs.give_socio_match

            give_vsl =
                inputs.give_vsl_usd2005
        end


        ozone_deaths =
            atmosphere_deaths *
            socioeconomic_scale


        physical_deaths +=
            ozone_deaths


        if give_socio_match

            socio_matched_deaths +=
                ozone_deaths
        end


        if !ismissing(
            give_vsl
        )

            valued_deaths +=
                ozone_deaths

            discount_factor =
                give_trial_discount_factor(
                    trialnum,
                    impact_year
                )

            monetary_value +=
                (
                    ozone_deaths /
                    1e6
                ) *
                Float64(
                    give_vsl
                ) *
                discount_factor
        end
    end


    ozone_monetary[
        trialnum
    ] =
        monetary_value


    socio_coverage[
        trialnum
    ] =
        physical_deaths ==
        0.0 ?
        1.0 :
        socio_matched_deaths /
        physical_deaths


    vsl_coverage[
        trialnum
    ] =
        physical_deaths ==
        0.0 ?
        1.0 :
        valued_deaths /
        physical_deaths
end


println(
    "Global ozone valuation complete."
)

println(
    "Mean ozone damage: ",
    round(
        mean(
            ozone_monetary
        ),
        digits = 3
    ),
    " USD2005/t CH4"
)

println(
    "Mean socioeconomic coverage: ",
    round(
        100 *
        mean(
            socio_coverage
        ),
        digits = 2
    ),
    "%"
)

println(
    "Mean VSL coverage: ",
    round(
        100 *
        mean(
            vsl_coverage
        ),
        digits = 2
    ),
    "%"
)

println()


# =====================================================================
# 10. Combine GIVE climate and ozone damages within each trial
# =====================================================================

extended_total =
    give_climate_total .+
    ozone_monetary


# =====================================================================
# 11. Build external factor tables
# =====================================================================

give_rows =
    make_factor_rows(
        trial_design,
        "give_climate_total_monetised",
        give_climate_total,
        "GIVE"
    )

ozone_rows =
    make_factor_rows(
        trial_design,
        "ozone_mortality_monetised",
        ozone_monetary,
        "McDuffie ozone + GIVE valuation"
    )

extended_rows =
    make_factor_rows(
        trial_design,
        "extended_total_monetised",
        extended_total,
        "GIVE + McDuffie ozone"
    )


factor_trials =
    vcat(
        give_rows,
        ozone_rows,
        extended_rows,
        cols =
            :setequal
    )

sort!(
    factor_trials,
    [
        :metric,
        :trialnum
    ]
)


factor_summary =
    summarize_factors(
        factor_trials
    )


# =====================================================================
# 12. QA
# =====================================================================

println(
    "QA"
)

println(
    "=="
)

println()


expected_trial_rows =
    N_TRIALS *
    3

nrow(
    factor_trials
) ==
    expected_trial_rows ||
    error(
        "Expected $expected_trial_rows trial rows, " *
        "found $(nrow(factor_trials))."
    )

println(
    "Trial row count: PASS (",
    nrow(
        factor_trials
    ),
    " rows)"
)


expected_summary_rows =
    3 *
    4

nrow(
    factor_summary
) ==
    expected_summary_rows ||
    error(
        "Expected $expected_summary_rows summary rows, " *
        "found $(nrow(factor_summary))."
    )

println(
    "Summary row count: PASS (",
    nrow(
        factor_summary
    ),
    " rows)"
)


all(
    isfinite,
    factor_trials.value_usd2005_per_t_ch4
) ||
    error(
        "Non-finite USD2005 factors detected."
    )

all(
    isfinite,
    factor_trials.value_usd2026_per_t_ch4
) ||
    error(
        "Non-finite USD2026 factors detected."
    )

println(
    "Finite-value QA: PASS"
)


converted_check =
    factor_trials.value_usd2005_per_t_ch4 .*
    CPI_UPRATING_FACTOR

maximum(
    abs.(
        converted_check .-
        factor_trials.value_usd2026_per_t_ch4
    )
) <
    1e-8 ||
    error(
        "USD2026 conversion QA failed."
    )

println(
    "Current-dollar conversion: PASS"
)


maximum(
    abs.(
        extended_total .-
        (
            give_climate_total .+
            ozone_monetary
        )
    )
) <
    1e-12 ||
    error(
        "Extended-total construction QA failed."
    )

println(
    "Extended-total construction: PASS"
)


pulse_df_error =
    maximum(
        abs.(
            [
                give_trial_discount_factor(
                    trialnum,
                    PULSE_YEAR
                ) -
                1.0

                for trialnum in
                    1:N_TRIALS
            ]
        )
    )

pulse_df_error <
    1e-12 ||
    error(
        "Pulse-year discount-factor QA failed."
    )

println(
    "Pulse-year discount factor: PASS"
)


# =====================================================================
# 13. Save
# =====================================================================

save(
    TRIAL_OUTPUT_PATH,
    factor_trials
)

save(
    SUMMARY_OUTPUT_PATH,
    factor_summary
)


# =====================================================================
# 14. Final console summary
# =====================================================================

println()
println(
    "2024 GLOBAL CH4 DAMAGE FACTOR BUILD COMPLETE"
)

println(
    "============================================"
)

println()

println(
    "Trial rows:   ",
    nrow(
        factor_trials
    )
)

println(
    "Summary rows: ",
    nrow(
        factor_summary
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
    "2024 mean factors:"
)

println(
    "  GIVE climate: ",
    round(
        mean(
            give_climate_total
        ) *
        CPI_UPRATING_FACTOR,
        digits = 2
    ),
    " USD2026/t CH4"
)

println(
    "  Ozone mortality: ",
    round(
        mean(
            ozone_monetary
        ) *
        CPI_UPRATING_FACTOR,
        digits = 2
    ),
    " USD2026/t CH4"
)

println(
    "  Extended total: ",
    round(
        mean(
            extended_total
        ) *
        CPI_UPRATING_FACTOR,
        digits = 2
    ),
    " USD2026/t CH4"
)

println()

println(
    "Headline GLLEX metric:"
)

println(
    "  extended_total_monetised"
)

println()

println(
    "Interpretation:"
)

println(
    "  expected discounted global societal damage " *
    "per tonne CH4 emitted in 2024"
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
    "Only global monetary damages are retained."
)

println(
    "No country, EU27 or physical-mortality outputs are written."
)