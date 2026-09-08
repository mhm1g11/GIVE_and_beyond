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

const SOCIO_SCALING_PATH = joinpath(
    OUTPUT_DIR,
    "give_momm_socioeconomic_scaling.csv"
)

const PHYSICAL_CUMULATIVE_PATH = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_cumulative_library_give_first.csv"
)

const COUNTRY_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_response_country_give_first.csv"
)

const SUMMARY_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_monetary_impact_library_give_first.csv"
)

println("BUILDING GIVE-FIRST OZONE MONETARY LIBRARY")
println("===========================================")
println()

# =====================================================================
# Robust CSV helpers
# =====================================================================

function as_bool(x)

    if ismissing(x)
        return false
    end

    value =
        lowercase(
            strip(
                string(x)
            )
        )

    return value in [
        "true",
        "t",
        "1",
        "yes",
        "y"
    ]
end


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

function geography_subset(
    df::DataFrame,
    geography::String
)

    if geography == "globe"

        return df

    elseif geography == "EU27"

        return filter(
            row ->
                !ismissing(row.iso3) &&
                string(row.iso3) in EU27,
            df
        )

    else

        return filter(
            row ->
                !ismissing(row.iso3) &&
                string(row.iso3) == geography,
            df
        )
    end
end

# =====================================================================
# 1. Load McDuffie ozone-health reference
#
# This contains the ozone-specific health calibration that GIVE lacks.
#
# We do NOT use:
#
#   McDuffie GDP
#   McDuffie VSL
#   McDuffie discounting
#
# anywhere in this script.
# =====================================================================

reference =
    load_momm_reference(
        MOMM_ROOT
    )

# =====================================================================
# 2. Load GIVE/McDuffie socioeconomic scaling
# =====================================================================

socio =
    DataFrame(
        load(
            SOCIO_SCALING_PATH
        )
    )

socio.year = [
    as_int(x)
    for x in socio.year
]

socio.socioeconomic_scale = [
    as_float(x)
    for x in socio.socioeconomic_scale
]

socio.give_match = [
    as_bool(x)
    for x in socio.give_match
]

# Only valid ISO3 entries can receive GIVE socioeconomic scaling.
socio_valid = filter(
    row ->
        !ismissing(row.iso3) &&
        !isempty(
            strip(
                string(row.iso3)
            )
        ),
    socio
)

socio_valid.join_iso3 = [
    strip(string(x))
    for x in socio_valid.iso3
]

socio_keep = select(
    socio_valid,
    :join_iso3,
    :year,
    :socioeconomic_scale,
    :give_match
)

# Ensure mapped rows remain unique.
duplicates = combine(
    groupby(
        socio_keep,
        [
            :join_iso3,
            :year
        ]
    ),
    nrow => :n
)

duplicates = filter(
    row -> row.n > 1,
    duplicates
)

nrow(duplicates) == 0 ||
    error(
        "Duplicate mapped ISO3/year rows in socioeconomic scaling."
    )

# =====================================================================
# 3. Run deterministic GIVE baseline
#
# This supplies:
#
#   country-specific VSL
#   global net per-capita consumption
#
# Both are native GIVE outputs.
# =====================================================================

println(
    "Running deterministic GIVE baseline for valuation..."
)

m =
    MimiGIVE.get_model()

run(m)

give_years =
    collect(
        dim_keys(
            m,
            :time
        )
    )

give_countries =
    string.(
        collect(
            dim_keys(
                m,
                :country
            )
        )
    )

vsl =
    m[
        :VSL,
        :vsl
    ]

global_cpc =
    m[
        :global_netconsumption,
        :net_cpc
    ]

year_index =
    Dict(
        Int(year) => i
        for (i, year) in
        enumerate(give_years)
    )

country_index =
    Dict(
        iso3 => i
        for (i, iso3) in
        enumerate(give_countries)
    )

println(
    "GIVE countries available for VSL: ",
    length(give_countries)
)

println()

# =====================================================================
# Ramsey discount factor
#
# This reproduces GIVE's no-equity-weighting SCC calculation:
#
# DF(t) =
#
#   ( CPC_pulse / CPC_t ) ^ ETA
#
#       ×
#
#   1 / (1 + PRTP) ^ (t - pulse_year)
#
#
# GIVE uses GLOBAL NET PER-CAPITA CONSUMPTION for this case.
# =====================================================================

function give_discount_factor(
    pulse_year::Int,
    impact_year::Int
)

    impact_year >= pulse_year ||
        return 0.0

    pulse_idx =
        year_index[pulse_year]

    impact_idx =
        year_index[impact_year]

    cpc_pulse =
        Float64(
            global_cpc[pulse_idx]
        )

    cpc_impact =
        Float64(
            global_cpc[impact_idx]
        )

    return (
        (cpc_pulse / cpc_impact)^ETA *
        1 /
        (1 + PRTP)^(
            impact_year -
            pulse_year
        )
    )
end

# =====================================================================
# 4. Detailed output table
#
# One observation represents:
#
# pulse year
# × impact year
# × McDuffie country/location
#
# Values are expressed per 1 tonne of CH4 avoided.
# =====================================================================

country_rows = DataFrame(
    pulse_year = Int[],
    impact_year = Int[],
    iso3 = String[],

    ozone_deaths_per_mt_ch4 = Float64[],
    ozone_deaths_per_t_ch4 = Float64[],

    socioeconomic_scale = Float64[],
    give_socioeconomic_match = Bool[],

    give_vsl_match = Bool[],

    give_vsl_usd2005 =
        Union{Missing, Float64}[],

    ramsey_discount_factor = Float64[],

    undiscounted_value_usd2005_per_t_ch4 =
        Union{Missing, Float64}[],

    discounted_value_usd2005_per_t_ch4 =
        Union{Missing, Float64}[]
)

# =====================================================================
# 5. Aggregated monetary impact library
# =====================================================================

summary_rows = DataFrame(
    pulse_year = Int[],
    geography = String[],
    impact_horizon = Int[],

    ozone_deaths_per_mt_ch4 = Float64[],

    valued_ozone_deaths_per_mt_ch4 = Float64[],

    give_vsl_coverage_share = Float64[],

    ozone_mortality_undiscounted_usd2005_per_t_ch4 =
        Float64[],

    ozone_mortality_monetised_usd2005_per_t_ch4 =
        Float64[]
)

# =====================================================================
# 6. Build valuation for every methane pulse year
# =====================================================================

for pulse_year in PULSE_YEARS

    println(
        "Pulse year: ",
        pulse_year
    )

    # -----------------------------------------------------------------
    # GIVE/FaIR methane perturbation
    # -----------------------------------------------------------------

    mm =
        MimiGIVE.get_marginal_model(
            m;
            year = pulse_year,
            gas = :CH4,
            pulse_size = PULSE_SIZE_MT
        )

    run(mm)

    mm_years =
        collect(
            dim_keys(
                mm.base,
                :time
            )
        )

    ch4_base =
        mm.base[
            :ch4_cycle,
            :CH₄
        ]

    ch4_modified =
        mm.modified[
            :ch4_cycle,
            :CH₄
        ]

    delta_ch4 =
        ch4_modified .-
        ch4_base

    years =
        collect(
            2020:IMPACT_HORIZON
        )

    indices = [
        findfirst(
            ==(year),
            mm_years
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
    # McDuffie ozone-health calibration
    #
    # Atmospheric methane already comes from GIVE/FaIR.
    # -----------------------------------------------------------------

    results =
        calculate_ozone_deaths(
            reference,
            years,
            methane_scales
        )

    rename!(
        results,
        :ozone_respiratory_deaths =>
            :atmosphere_only_deaths
    )

    # -----------------------------------------------------------------
    # Apply GIVE socioeconomic scaling
    # -----------------------------------------------------------------

    results.join_iso3 = [
        ismissing(x) ?
            "" :
            strip(string(x))
        for x in results.iso3
    ]

    results = leftjoin(
        results,
        socio_keep,
        on = [
            :join_iso3,
            :year
        ]
    )

    results.give_match = [
        ismissing(x) ?
            false :
            as_bool(x)
        for x in results.give_match
    ]

    results.socioeconomic_scale = [
        ismissing(x) ?
            1.0 :
            as_float(x)
        for x in
        results.socioeconomic_scale
    ]

    results.ozone_respiratory_deaths =
        results.atmosphere_only_deaths .*
        results.socioeconomic_scale

    # -----------------------------------------------------------------
    # Native GIVE valuation
    # -----------------------------------------------------------------

    for row in eachrow(results)

        impact_year =
            Int(row.year)

        # GIVE's SCC calculation begins in the pulse year.
        impact_year < pulse_year &&
            continue

        iso3 =
            ismissing(row.iso3) ?
                "" :
                strip(
                    string(row.iso3)
                )

        deaths_per_mt =
            Float64(
                row.ozone_respiratory_deaths
            )

        # 1 Mt = 1,000,000 tonnes.
        deaths_per_t =
            deaths_per_mt /
            1e6

        discount_factor =
            give_discount_factor(
                pulse_year,
                impact_year
            )

        # -------------------------------------------------------------
        # Country VSL
        #
        # Only countries represented in GIVE can receive a GIVE VSL.
        #
        # We deliberately do NOT fall back to McDuffie's VSL.
        # -------------------------------------------------------------

        has_vsl =
            !isempty(iso3) &&
            haskey(
                country_index,
                iso3
            ) &&
            haskey(
                year_index,
                impact_year
            )

        if has_vsl

            ci =
                country_index[iso3]

            yi =
                year_index[impact_year]

            raw_vsl =
                vsl[
                    yi,
                    ci
                ]

            if ismissing(raw_vsl)

                has_vsl =
                    false
            end
        end

        if has_vsl

            give_vsl =
                Float64(
                    vsl[
                        year_index[impact_year],
                        country_index[iso3]
                    ]
                )

            undiscounted_value =
                deaths_per_t *
                give_vsl

            discounted_value =
                undiscounted_value *
                discount_factor

            push!(
                country_rows,
                (
                    pulse_year,
                    impact_year,
                    iso3,

                    deaths_per_mt,
                    deaths_per_t,

                    Float64(
                        row.socioeconomic_scale
                    ),

                    Bool(
                        row.give_match
                    ),

                    true,

                    give_vsl,

                    discount_factor,

                    undiscounted_value,

                    discounted_value
                )
            )

        else

            push!(
                country_rows,
                (
                    pulse_year,
                    impact_year,
                    iso3,

                    deaths_per_mt,
                    deaths_per_t,

                    Float64(
                        row.socioeconomic_scale
                    ),

                    Bool(
                        row.give_match
                    ),

                    false,

                    missing,

                    discount_factor,

                    missing,

                    missing
                )
            )
        end
    end

    # -----------------------------------------------------------------
    # Aggregate globe / EU27 / Germany
    # -----------------------------------------------------------------

    pulse_rows = filter(
        row ->
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
                pulse_rows,
                geography
            )

        physical_deaths =
            sum(
                geo.ozone_deaths_per_mt_ch4
            )

        valued =
            filter(
                row ->
                    row.give_vsl_match,
                geo
            )

        valued_deaths =
            sum(
                valued.ozone_deaths_per_mt_ch4
            )

        coverage =
            physical_deaths == 0.0 ?
                1.0 :
                valued_deaths /
                physical_deaths

        undiscounted_value =
            sum(
                skipmissing(
                    geo.undiscounted_value_usd2005_per_t_ch4
                )
            )

        discounted_value =
            sum(
                skipmissing(
                    geo.discounted_value_usd2005_per_t_ch4
                )
            )

        push!(
            summary_rows,
            (
                pulse_year,
                geography,
                IMPACT_HORIZON,

                physical_deaths,

                valued_deaths,

                coverage,

                undiscounted_value,

                discounted_value
            )
        )

        println(
            "  ",
            rpad(
                geography,
                6
            ),
            ": ",
            round(
                discounted_value,
                digits = 3
            ),
            " USD2005/t CH4",
            " | deaths ",
            round(
                physical_deaths,
                digits = 3
            ),
            "/Mt",
            " | VSL coverage ",
            round(
                100 * coverage,
                digits = 2
            ),
            "%"
        )
    end

    println()
end

# =====================================================================
# 7. QA against previously validated physical ozone library
#
# The deaths reconstructed in this valuation script must match the
# final physical response library exactly.
# =====================================================================

physical_reference =
    DataFrame(
        load(
            PHYSICAL_CUMULATIVE_PATH
        )
    )

physical_reference.pulse_year = [
    as_int(x)
    for x in
    physical_reference.pulse_year
]

physical_reference.cumulative_deaths_per_mt_ch4 = [
    as_float(x)
    for x in
    physical_reference.cumulative_deaths_per_mt_ch4
]

qa = leftjoin(
    summary_rows,
    select(
        physical_reference,
        :pulse_year,
        :geography,
        :cumulative_deaths_per_mt_ch4
    ),
    on = [
        :pulse_year,
        :geography
    ]
)

qa.physical_difference = (
    qa.ozone_deaths_per_mt_ch4 .-
    qa.cumulative_deaths_per_mt_ch4
)

max_physical_difference =
    maximum(
        abs.(
            qa.physical_difference
        )
    )

println(
    "PHYSICAL LIBRARY QA"
)

println(
    "==================="
)

println(
    "Maximum absolute deaths/Mt difference: ",
    max_physical_difference
)

max_physical_difference < 1e-8 ||
    error(
        "Ozone valuation does not reproduce the validated physical library."
    )

println(
    "PASS: monetary library reproduces physical ozone mortality."
)

println()

# =====================================================================
# 8. Discounting QA
# =====================================================================

println(
    "DISCOUNTING QA"
)

println(
    "=============="
)

for pulse_year in PULSE_YEARS

    df0 =
        give_discount_factor(
            pulse_year,
            pulse_year
        )

    println(
        pulse_year,
        " pulse-year discount factor = ",
        df0
    )

    abs(df0 - 1.0) < 1e-12 ||
        error(
            "Pulse-year discount factor should equal 1."
        )
end

println(
    "PASS: pulse-year discount factors equal 1."
)

println()

# =====================================================================
# 9. Save
# =====================================================================

sort!(
    country_rows,
    [
        :pulse_year,
        :iso3,
        :impact_year
    ]
)

sort!(
    summary_rows,
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

println(
    "GIVE-FIRST OZONE MONETARY LIBRARY COMPLETE"
)

println(
    "==========================================="
)

println()

println(
    "Country-year rows: ",
    nrow(country_rows)
)

println(
    "Summary rows: ",
    nrow(summary_rows)
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

println()

println(
    "INTERPRETATION"
)

println(
    "=============="
)

println(
    "Ozone respiratory deaths use GIVE/FaIR methane, GIVE population, " *
    "GIVE all-cause mortality, and the McDuffie ozone-health calibration."
)

println(
    "Valuation uses GIVE country/year VSL in USD2005."
)

println(
    "Discounting uses GIVE global net per-capita consumption with " *
    "PRTP = $(PRTP) and ETA = $(ETA)."
)

println(
    "No McDuffie VSL, GDP, income elasticity, or discounting is used."
)

println(
    "Countries without a GIVE VSL remain in physical mortality totals " *
    "but are deliberately excluded from monetary totals and reported " *
    "through the VSL coverage statistic."
)

println()

println(
    "NOTE:"
)

println(
    "This is the deterministic ozone valuation library. " *
    "It should be validated before adding ozone to the current " *
    "5-trial policy monetary summary."
)