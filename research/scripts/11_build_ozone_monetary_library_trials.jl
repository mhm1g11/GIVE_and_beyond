using Random
using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics

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

const MCS_OUTPUT_DIR = joinpath(
    OUTPUT_DIR,
    "ozone_mcs_socioeconomic_inputs"
)

const COUNTRY_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_response_country_trials.csv"
)

const SUMMARY_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_impact_library_trials.csv"
)

const SUMMARY_STATS_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_impact_library_trials_summary.csv"
)

const MC_SEED = 20260908

println("BUILDING TRIAL-ALIGNED GIVE-FIRST OZONE MONETARY LIBRARY")
println("=========================================================")
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


function as_float_or_missing(x)

    if ismissing(x)
        return missing
    end

    if x isa Real
        value = Float64(x)

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


function geography_subset(
    df::DataFrame,
    geography::String
)

    if geography == "globe"

        return df

    elseif geography == "EU27"

        return filter(
            row ->
                !isempty(row.iso3) &&
                row.iso3 in EU27,
            df
        )

    else

        return filter(
            row ->
                row.iso3 == geography,
            df
        )
    end
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

N_TRIALS =
    nrow(
        trial_design
    )

rffsp_ids =
    collect(
        trial_design.rffsp_id
    )

fair_ids =
    collect(
        trial_design.fair_parameter_set_id
    )

println(
    "Trials: ",
    N_TRIALS
)

for row in eachrow(trial_design)

    println(
        "  Trial ",
        row.trialnum,
        ": RFF ",
        row.rffsp_id,
        " | FaIR ",
        row.fair_parameter_set_id
    )
end

println()

# =====================================================================
# 2. Load McDuffie socioeconomic reference denominators
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
        strip(string(x))
    for x in momm_socio.iso3
]

# Only nonblank ISO3 mappings can link to GIVE.
momm_valid = filter(
    row ->
        !isempty(row.iso3_clean),
    momm_socio
)

duplicates = combine(
    groupby(
        momm_valid,
        [
            :iso3_clean,
            :year
        ]
    ),
    nrow => :n
)

duplicates = filter(
    row ->
        row.n > 1,
    duplicates
)

nrow(duplicates) == 0 ||
    error(
        "Duplicate mapped McDuffie ISO3/year rows found."
    )

# =====================================================================
# 3. Run GIVE Monte Carlo
#
# Extract:
#   population
#   all-cause mortality
#   VSL
#   global net per-capita consumption
#
# using the explicit master trial design.
# =====================================================================

println(
    "Running GIVE MCS for trial-specific socioeconomic and valuation inputs..."
)

if isdir(MCS_OUTPUT_DIR)

    rm(
        MCS_OUTPUT_DIR;
        recursive = true
    )
end

m =
    MimiGIVE.get_model()

Random.seed!(
    MC_SEED
)

mcs =
    MimiGIVE.run_mcs(
        trials = N_TRIALS,

        m = m,

        fair_parameter_set = :deterministic,
        fair_parameter_set_ids = fair_ids,

        rffsp_sampling = :deterministic,
        rffsp_sampling_ids = rffsp_ids,

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

        output_dir = MCS_OUTPUT_DIR,

        results_in_memory = true
    )

println(
    "GIVE MCS complete."
)

println()

# =====================================================================
# 4. Extract trial-specific GIVE variables
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

# ---------------------------------------------------------------------
# Country-level variable cleaner
# ---------------------------------------------------------------------

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
            strip(string(x))
        for x in clean.iso3
    ]

    clean[!, output_value] =
        as_float_or_missing.(
            clean[!, output_value]
        )

    return clean
end

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

# ---------------------------------------------------------------------
# Global consumption
# ---------------------------------------------------------------------

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

cpc = select(
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

# Analysis horizon only.
population = filter(
    row ->
        2020 <= row.year <= IMPACT_HORIZON,
    population
)

deathrate = filter(
    row ->
        2020 <= row.year <= IMPACT_HORIZON,
    deathrate
)

vsl = filter(
    row ->
        2020 <= row.year <= IMPACT_HORIZON,
    vsl
)

cpc = filter(
    row ->
        2020 <= row.year <= IMPACT_HORIZON,
    cpc
)

# =====================================================================
# 5. QA missing GIVE values
# =====================================================================

println("GIVE input missing-value QA")
println("---------------------------")

println(
    "Population missing: ",
    count(ismissing, population.give_population_millions)
)

println(
    "Deathrate missing: ",
    count(ismissing, deathrate.give_deathrate_per_thousand)
)

println(
    "VSL missing: ",
    count(ismissing, vsl.give_vsl_usd2005)
)

println(
    "Global net CPC missing: ",
    count(ismissing, cpc.global_net_cpc)
)

println()

# =====================================================================
# 6. Merge GIVE trial inputs
#
# Population is the base country-year table.
#
# VSL is LEFT joined deliberately:
# a missing VSL must not remove physical mortality.
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

println(
    "Trial-country-year GIVE rows: ",
    nrow(give_socio)
)

println(
    "Trial-year consumption rows: ",
    nrow(cpc)
)

println()

# =====================================================================
# 7. Add McDuffie reference denominators
# =====================================================================

momm_join = select(
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

# ---------------------------------------------------------------------
# Compute scaling safely.
#
# If GIVE population/mortality or the McDuffie denominator is missing,
# the socioeconomic scaling falls back to 1.0.
#
# This mirrors the deterministic GIVE-first implementation.
# ---------------------------------------------------------------------

trial_socio.population_scale =
    Vector{Float64}(
        undef,
        nrow(trial_socio)
    )

trial_socio.mortality_scale =
    Vector{Float64}(
        undef,
        nrow(trial_socio)
    )

trial_socio.socioeconomic_scale =
    Vector{Float64}(
        undef,
        nrow(trial_socio)
    )

trial_socio.give_socio_match =
    Vector{Bool}(
        undef,
        nrow(trial_socio)
    )

for (i, row) in enumerate(
    eachrow(trial_socio)
)

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

    if pop_ok && mort_ok

        momm_population_millions =
            Float64(
                row.reference_population_thousands
            ) / 1000

        give_mortality_rate =
            Float64(
                row.give_deathrate_per_thousand
            ) / 1000

        pop_scale =
            Float64(
                row.give_population_millions
            ) /
            momm_population_millions

        mort_scale =
            give_mortality_rate /
            Float64(
                row.reference_allcause_mortality_rate
            )

        trial_socio.population_scale[i] =
            pop_scale

        trial_socio.mortality_scale[i] =
            mort_scale

        trial_socio.socioeconomic_scale[i] =
            pop_scale * mort_scale

        trial_socio.give_socio_match[i] =
            true

    else

        trial_socio.population_scale[i] =
            1.0

        trial_socio.mortality_scale[i] =
            1.0

        trial_socio.socioeconomic_scale[i] =
            1.0

        trial_socio.give_socio_match[i] =
            false
    end
end

# =====================================================================
# 8. Build socioeconomic lookup
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
        Int(row.trialnum),
        string(row.iso3),
        Int(row.year)
    )

    socio_lookup[key] = (
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

# =====================================================================
# 9. Ramsey discounting lookup
# =====================================================================

cpc_lookup =
    Dict{
        Tuple{Int, Int},
        Float64
    }()

for row in eachrow(cpc)

    if !ismissing(
        row.global_net_cpc
    )

        cpc_lookup[
            (
                Int(row.trialnum),
                Int(row.year)
            )
        ] =
            Float64(
                row.global_net_cpc
            )
    end
end

function give_trial_discount_factor(
    trialnum::Int,
    pulse_year::Int,
    impact_year::Int
)

    impact_year < pulse_year &&
        return 0.0

    pulse_key = (
        trialnum,
        pulse_year
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
            "Missing GIVE global net CPC for trial $trialnum, year $pulse_year."
        )

    haskey(
        cpc_lookup,
        impact_key
    ) ||
        error(
            "Missing GIVE global net CPC for trial $trialnum, year $impact_year."
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
        (cpc_pulse / cpc_impact)^ETA
        /
        (1 + PRTP)^(
            impact_year -
            pulse_year
        )
    )
end

# =====================================================================
# 10. Load McDuffie ozone-health calibration
# =====================================================================

reference =
    load_momm_reference(
        MOMM_ROOT
    )

# =====================================================================
# 11. Output tables
# =====================================================================

country_rows = DataFrame(
    trialnum = Int[],
    rffsp_id = Int[],
    fair_parameter_set_id = Int[],
    pulse_year = Int[],
    impact_year = Int[],
    iso3 = String[],

    atmosphere_only_deaths_per_mt_ch4 = Float64[],

    socioeconomic_scale = Float64[],
    give_socio_match = Bool[],

    ozone_deaths_per_mt_ch4 = Float64[],

    give_vsl_match = Bool[],
    give_vsl_usd2005 =
        Union{Missing, Float64}[],

    ramsey_discount_factor = Float64[],

    ozone_value_usd2005_per_t_ch4 =
        Union{Missing, Float64}[]
)

summary_rows = DataFrame(
    trialnum = Int[],
    rffsp_id = Int[],
    fair_parameter_set_id = Int[],
    pulse_year = Int[],
    geography = String[],

    ozone_deaths_per_mt_ch4 = Float64[],

    give_socio_coverage_share = Float64[],
    give_vsl_coverage_share = Float64[],

    ozone_mortality_monetised_usd2005_per_t_ch4 =
        Float64[]
)

# =====================================================================
# 12. Build trial-aligned ozone response and valuation
# =====================================================================

for pulse_year in PULSE_YEARS

    println(
        "Pulse year: ",
        pulse_year
    )

    # -----------------------------------------------------------------
    # Common atmospheric CH4 impulse
    #
    # Script 10 demonstrated that this is invariant across trials to
    # numerical precision.
    # -----------------------------------------------------------------

    m_det =
        MimiGIVE.get_model()

    mm =
        MimiGIVE.get_marginal_model(
            m_det;
            year = pulse_year,
            gas = :CH4,
            pulse_size = PULSE_SIZE_MT
        )

    run(mm)

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
            2020:IMPACT_HORIZON
        )

    indices = [
        findfirst(
            ==(year),
            give_years
        )
        for year in years
    ]

    any(isnothing, indices) &&
        error(
            "Required year missing from GIVE."
        )

    give_delta = [
        Float64(
            delta_ch4[idx]
        )
        for idx in indices
    ]

    methane_scales =
        give_methane_scaling(
            years,
            give_delta
        )

    # -----------------------------------------------------------------
    # McDuffie central ozone-health calibration
    # -----------------------------------------------------------------

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

    # ================================================================
    # Trial loop
    # ================================================================

    for trial in eachrow(
        trial_design
    )

        trialnum =
            Int(
                trial.trialnum
            )

        rffsp_id =
            Int(
                trial.rffsp_id
            )

        fair_id =
            Int(
                trial.fair_parameter_set_id
            )

        # -------------------------------------------------------------
        # Work through every McDuffie country/location-year.
        #
        # Importantly, blank/unmapped ISO3 rows remain here.
        # -------------------------------------------------------------

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

            # Default for McDuffie locations not represented in GIVE:
            #
            # socioeconomic scale = 1
            # no GIVE VSL
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

            discount_factor =
                give_trial_discount_factor(
                    trialnum,
                    pulse_year,
                    impact_year
                )

            give_vsl_match =
                !ismissing(
                    give_vsl
                )

            ozone_value =
                if give_vsl_match

                    (
                        ozone_deaths /
                        1e6
                    ) *
                    Float64(
                        give_vsl
                    ) *
                    discount_factor

                else

                    missing
                end

            push!(
                country_rows,
                (
                    trialnum,
                    rffsp_id,
                    fair_id,
                    pulse_year,
                    impact_year,
                    iso3,

                    atmosphere_deaths,

                    socioeconomic_scale,
                    give_socio_match,

                    ozone_deaths,

                    give_vsl_match,
                    give_vsl,

                    discount_factor,

                    ozone_value
                )
            )
        end

        # -------------------------------------------------------------
        # Aggregate this pulse/trial
        # -------------------------------------------------------------

        trial_pulse_rows = filter(
            row ->
                row.trialnum ==
                    trialnum &&
                row.pulse_year ==
                    pulse_year,
            country_rows
        )

        for geography in [
            "globe",
            "EU27",
            "DEU"
        ]

            geo =
                geography_subset(
                    trial_pulse_rows,
                    geography
                )

            physical_deaths =
                sum(
                    geo.ozone_deaths_per_mt_ch4
                )

            socio_matched_deaths =
                sum(
                    row.ozone_deaths_per_mt_ch4
                    for row in eachrow(geo)
                    if row.give_socio_match
                )

            valued_deaths =
                sum(
                    row.ozone_deaths_per_mt_ch4
                    for row in eachrow(geo)
                    if row.give_vsl_match
                )

            socio_coverage =
                physical_deaths == 0.0 ?
                    1.0 :
                    socio_matched_deaths /
                    physical_deaths

            vsl_coverage =
                physical_deaths == 0.0 ?
                    1.0 :
                    valued_deaths /
                    physical_deaths

            monetary_value =
                sum(
                    skipmissing(
                        geo.ozone_value_usd2005_per_t_ch4
                    )
                )

            push!(
                summary_rows,
                (
                    trialnum,
                    rffsp_id,
                    fair_id,
                    pulse_year,
                    geography,

                    physical_deaths,

                    socio_coverage,
                    vsl_coverage,

                    monetary_value
                )
            )
        end
    end

    println(
        "  completed ",
        N_TRIALS,
        " aligned trials"
    )
end

# =====================================================================
# 13. Monte Carlo summary statistics
# =====================================================================

summary_stats = combine(
    groupby(
        summary_rows,
        [
            :pulse_year,
            :geography
        ]
    ),

    :ozone_deaths_per_mt_ch4 =>
        mean =>
        :mean_deaths_per_mt_ch4,

    :ozone_deaths_per_mt_ch4 =>
        median =>
        :median_deaths_per_mt_ch4,

    :ozone_deaths_per_mt_ch4 =>
        (
            x ->
                quantile(
                    x,
                    0.025
                )
        ) =>
        :p2_5_deaths_per_mt_ch4,

    :ozone_deaths_per_mt_ch4 =>
        (
            x ->
                quantile(
                    x,
                    0.975
                )
        ) =>
        :p97_5_deaths_per_mt_ch4,

    :ozone_mortality_monetised_usd2005_per_t_ch4 =>
        mean =>
        :mean_usd2005_per_t_ch4,

    :ozone_mortality_monetised_usd2005_per_t_ch4 =>
        median =>
        :median_usd2005_per_t_ch4,

    :ozone_mortality_monetised_usd2005_per_t_ch4 =>
        (
            x ->
                quantile(
                    x,
                    0.025
                )
        ) =>
        :p2_5_usd2005_per_t_ch4,

    :ozone_mortality_monetised_usd2005_per_t_ch4 =>
        (
            x ->
                quantile(
                    x,
                    0.975
                )
        ) =>
        :p97_5_usd2005_per_t_ch4,

    :give_socio_coverage_share =>
        mean =>
        :mean_give_socio_coverage,

    :give_vsl_coverage_share =>
        mean =>
        :mean_give_vsl_coverage,

    nrow =>
        :n_trials
)

# =====================================================================
# 14. QA
# =====================================================================

println()
println("QA")
println("==")
println()

# Pulse-year discount factor must equal 1.
max_pulse_df_error =
    maximum(
        abs.(
            [
                give_trial_discount_factor(
                    Int(row.trialnum),
                    year,
                    year
                ) - 1.0
                for row in eachrow(
                    trial_design
                )
                for year in PULSE_YEARS
            ]
        )
    )

println(
    "Maximum pulse-year discount-factor error: ",
    max_pulse_df_error
)

max_pulse_df_error < 1e-12 ||
    error(
        "Pulse-year discounting QA failed."
    )

println(
    "PASS: pulse-year discount factors equal 1."
)

println()

# ---------------------------------------------------------------------
# Print 2025 trial dispersion
# ---------------------------------------------------------------------

qa_2025 = filter(
    row ->
        row.pulse_year ==
        2025,
    summary_rows
)

println(
    "2025 trial dispersion"
)

println(
    "---------------------"
)

for geography in [
    "globe",
    "EU27",
    "DEU"
]

    geo = filter(
        row ->
            row.geography ==
            geography,
        qa_2025
    )

    println()
    println(
        geography
    )

    for row in eachrow(geo)

        println(
            "  Trial ",
            row.trialnum,
            " | RFF ",
            row.rffsp_id,
            " | deaths ",
            round(
                row.ozone_deaths_per_mt_ch4,
                digits = 3
            ),
            "/Mt",
            " | value ",
            round(
                row.ozone_mortality_monetised_usd2005_per_t_ch4,
                digits = 3
            ),
            " USD2005/t",
            " | socio coverage ",
            round(
                100 *
                row.give_socio_coverage_share,
                digits = 2
            ),
            "%",
            " | VSL coverage ",
            round(
                100 *
                row.give_vsl_coverage_share,
                digits = 2
            ),
            "%"
        )
    end
end

# =====================================================================
# 15. Save
# =====================================================================

sort!(
    country_rows,
    [
        :trialnum,
        :pulse_year,
        :iso3,
        :impact_year
    ]
)

sort!(
    summary_rows,
    [
        :trialnum,
        :pulse_year,
        :geography
    ]
)

sort!(
    summary_stats,
    [
        :pulse_year,
        :geography
    ]
)

save(
    COUNTRY_OUTPUT,
    country_rows
)

save(
    SUMMARY_OUTPUT,
    summary_rows
)

save(
    SUMMARY_STATS_OUTPUT,
    summary_stats
)

println()
println(
    "TRIAL-ALIGNED OZONE MONETARY LIBRARY COMPLETE"
)

println(
    "============================================="
)

println()

println(
    "Detailed rows: ",
    nrow(country_rows)
)

println(
    "Trial summary rows: ",
    nrow(summary_rows)
)

println(
    "Statistical summary rows: ",
    nrow(summary_stats)
)

println()

println(
    "Saved:"
)

println(
    "  ",
    COUNTRY_OUTPUT
)

println(
    "  ",
    SUMMARY_OUTPUT
)

println(
    "  ",
    SUMMARY_STATS_OUTPUT
)

println()
println(
    "INTERPRETATION"
)

println(
    "=============="
)

println(
    "Atmospheric CH4 response is common across trials, based on " *
    "the validated script-10 diagnostic."
)

println(
    "Each ozone trial inherits the explicit RFF socioeconomic " *
    "trajectory defined in mc_trial_design.csv."
)

println(
    "Population, all-cause mortality, VSL and Ramsey consumption " *
    "discounting therefore vary coherently within each GIVE trial."
)

println(
    "Countries without GIVE socioeconomic inputs retain " *
    "socioeconomic scale = 1."
)

println(
    "Countries without GIVE VSL remain in physical mortality totals " *
    "but are excluded from monetary valuation."
)

println(
    "McDuffie's ozone-health response remains at its central estimate."
)

println(
    "McDuffie-specific ozone-health uncertainty has not yet been added."
)