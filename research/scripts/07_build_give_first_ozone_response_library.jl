using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames

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

const ANNUAL_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_response_library_give_first.csv"
)

const CUMULATIVE_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_cumulative_library_give_first.csv"
)

println("BUILDING FULL GIVE-FIRST OZONE MORTALITY RESPONSE LIBRARY")
println("==========================================================")
println()

# =====================================================================
# Helpers for robust CSV type conversion
# =====================================================================

function as_bool(x)

    if ismissing(x)
        return false
    end

    value = lowercase(strip(string(x)))

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
# Load McDuffie ozone-health reference
#
# This retains the ozone-specific health calibration that GIVE lacks.
# =====================================================================

reference =
    load_momm_reference(MOMM_ROOT)

# =====================================================================
# Load GIVE / McDuffie socioeconomic scaling
# =====================================================================

socio =
    DataFrame(load(SOCIO_SCALING_PATH))

# Normalize CSV types explicitly.
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

# =====================================================================
# Keep only mapped ISO3 rows for GIVE socioeconomic scaling
#
# Blank ISO3 rows are distinct McDuffie locations that do not map to
# GIVE. They remain in global mortality calculations with scaling = 1.
# =====================================================================

socio_valid = filter(
    row ->
        !ismissing(row.iso3) &&
        !isempty(strip(string(row.iso3))),
    socio
)

socio_valid.join_iso3 = [
    strip(string(x))
    for x in socio_valid.iso3
]

# =====================================================================
# QA: mapped ISO3/year rows must genuinely be unique
# =====================================================================

duplicates = combine(
    groupby(
        socio_valid,
        [:join_iso3, :year]
    ),
    nrow => :n
)

duplicates = filter(
    row -> row.n > 1,
    duplicates
)

nrow(duplicates) == 0 ||
    error(
        "Duplicate non-blank ISO3/year rows found in socioeconomic scaling table."
    )

socio_keep = select(
    socio_valid,
    :join_iso3,
    :year,
    :socioeconomic_scale,
    :give_match
)

println(
    "Valid mapped socioeconomic country-year rows: ",
    nrow(socio_valid)
)

println(
    "Blank/unmapped country-year rows retained at scale 1: ",
    nrow(socio) - nrow(socio_valid)
)

println()

# =====================================================================
# Output tables
# =====================================================================

annual_rows = DataFrame(
    pulse_year = Int[],
    impact_year = Int[],
    geography = String[],
    deaths_per_t_ch4 = Float64[],
    atmosphere_only_deaths_per_t_ch4 = Float64[],
    give_match_coverage_share = Float64[]
)

cumulative_rows = DataFrame(
    pulse_year = Int[],
    geography = String[],
    impact_horizon = Int[],
    cumulative_deaths_per_t_ch4 = Float64[],
    cumulative_deaths_per_mt_ch4 = Float64[],
    atmosphere_only_deaths_per_mt_ch4 = Float64[],
    socioeconomic_adjustment_ratio = Float64[],
    give_match_coverage_share = Float64[]
)

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
# Build GIVE-first response library
# =====================================================================

for pulse_year in PULSE_YEARS

    println("Pulse year: ", pulse_year)

    # =================================================================
    # 1. GIVE / FaIR methane perturbation
    # =================================================================

    m =
        MimiGIVE.get_model()

    mm =
        MimiGIVE.get_marginal_model(
            m;
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
            give_years
        )
        for year in years
    ]

    any(isnothing, indices) &&
        error(
            "A required year is missing from the GIVE model."
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

    # =================================================================
    # 2. McDuffie ozone-health calibration
    #
    # Methane concentration dynamics now come entirely from GIVE/FaIR.
    # =================================================================

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

    # =================================================================
    # 3. Apply GIVE socioeconomic scaling
    # =================================================================

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

    # Unmatched locations retain McDuffie socioeconomic level.
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
        for x in results.socioeconomic_scale
    ]

    # -----------------------------------------------------------------
    # Preferred GIVE-first ozone mortality
    #
    # McDuffie ozone-health calibration
    # × GIVE/FaIR methane perturbation
    # × GIVE population scaling
    # × GIVE all-cause mortality scaling
    # -----------------------------------------------------------------

    results.ozone_respiratory_deaths =
        results.atmosphere_only_deaths .*
        results.socioeconomic_scale

    # =================================================================
    # 4. Geography aggregation
    # =================================================================

    for geography in [
        "globe",
        "EU27",
        "DEU"
    ]

        subset =
            geography_subset(
                results,
                geography
            )

        # =============================================================
        # Annual response
        # =============================================================

        for impact_year in years

            year_subset = filter(
                row ->
                    Int(row.year) ==
                    impact_year,
                subset
            )

            atmosphere_deaths =
                sum(
                    Float64.(
                        year_subset.atmosphere_only_deaths
                    )
                )

            give_first_deaths =
                sum(
                    Float64.(
                        year_subset.ozone_respiratory_deaths
                    )
                )

            matched_deaths =
                sum(
                    Float64(
                        row.atmosphere_only_deaths
                    )
                    for row in eachrow(year_subset)
                    if row.give_match
                )

            coverage =
                atmosphere_deaths == 0.0 ?
                    1.0 :
                    matched_deaths /
                    atmosphere_deaths

            # Model pulse is 1 Mt CH4 = 1,000,000 tonnes.
            push!(
                annual_rows,
                (
                    pulse_year,
                    impact_year,
                    geography,

                    give_first_deaths / 1e6,

                    atmosphere_deaths / 1e6,

                    coverage
                )
            )
        end

        # =============================================================
        # Cumulative response
        # =============================================================

        atmosphere_total =
            sum(
                Float64.(
                    subset.atmosphere_only_deaths
                )
            )

        give_first_total =
            sum(
                Float64.(
                    subset.ozone_respiratory_deaths
                )
            )

        matched_total =
            sum(
                Float64(
                    row.atmosphere_only_deaths
                )
                for row in eachrow(subset)
                if row.give_match
            )

        coverage =
            atmosphere_total == 0.0 ?
                1.0 :
                matched_total /
                atmosphere_total

        adjustment_ratio =
            atmosphere_total == 0.0 ?
                1.0 :
                give_first_total /
                atmosphere_total

        push!(
            cumulative_rows,
            (
                pulse_year,
                geography,
                IMPACT_HORIZON,

                # per tonne
                give_first_total / 1e6,

                # per Mt
                give_first_total,

                # previous atmosphere-only result
                atmosphere_total,

                # effect of GIVE socioeconomic substitution
                adjustment_ratio,

                # mortality-weighted GIVE coverage
                coverage
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
                give_first_total,
                digits = 3
            ),
            " deaths/Mt",
            " | previous ",
            round(
                atmosphere_total,
                digits = 3
            ),
            " | socio ratio ",
            round(
                adjustment_ratio,
                digits = 4
            ),
            " | GIVE mortality coverage ",
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
# Save
# =====================================================================

sort!(
    annual_rows,
    [
        :pulse_year,
        :geography,
        :impact_year
    ]
)

sort!(
    cumulative_rows,
    [
        :pulse_year,
        :geography
    ]
)

save(
    ANNUAL_OUTPUT,
    annual_rows
)

save(
    CUMULATIVE_OUTPUT,
    cumulative_rows
)

println("GIVE-FIRST OZONE RESPONSE LIBRARY COMPLETE")
println("==========================================")
println()

println(
    "Annual rows: ",
    nrow(annual_rows)
)

println(
    "Cumulative rows: ",
    nrow(cumulative_rows)
)

println()
println("Saved:")
println("  ", ANNUAL_OUTPUT)
println("  ", CUMULATIVE_OUTPUT)

println()
println("INTERPRETATION")
println("==============")

println(
    "Preferred ozone mortality uses GIVE/FaIR methane, " *
    "GIVE population, and GIVE all-cause mortality trajectories."
)

println(
    "McDuffie is retained only for the methane-induced ozone " *
    "respiratory health calibration that GIVE does not provide."
)

println(
    "McDuffie locations without a usable GIVE country mapping " *
    "retain socioeconomic scale = 1."
)

println(
    "GIVE mortality coverage is impact-weighted."
)