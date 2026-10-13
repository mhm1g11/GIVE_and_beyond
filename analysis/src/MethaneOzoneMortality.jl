module MethaneOzoneMortality

using FileIO
using CSVFiles
using DataFrames

export load_momm_reference,
       legacy_methane_scaling,
       reference_methane_delta_ppb,
       give_methane_scaling,
       calculate_ozone_deaths,
       aggregate_geography,
       EU27

# ================================================================
# McDuffie / MOMM-RFT reference constants
#
# These are retained to reproduce and rescale the original BenMAP
# methane-ozone mortality experiment.
# ================================================================

const REFERENCE_PULSE_YEAR = 2020
const REFERENCE_PULSE_MT = 275.0
const METHANE_MT_PER_PPB = 2.75
const REFERENCE_METHANE_LIFETIME = 11.8

const EU27 = [
    "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK",
    "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL",
    "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL",
    "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"
]

# ================================================================
# Load minimum MOMM-RFT reference data
# ================================================================

const ATMOSPHERIC_MODELS = ("MMM", "CESM2", "GFDL", "GISS", "HadGEM", "MIROC")
const HEALTH_RESPONSE_COLUMNS = Dict(
    "lower" => Symbol("Inverse.2_5"),
    "central" => Symbol("Inverse.PE"),
    "upper" => Symbol("Inverse.97_5")
)

"""
Load one stored atmospheric/epidemiological response. The default preserves the
production MMM central calibration. Alternatives are sensitivity cases, not
probabilistic draws and not FaIR ozone radiative-forcing parameters.
"""
function load_momm_reference(
    momm_root::String;
    atmospheric_model::String = "MMM",
    health_response::String = "central"
)
    atmospheric_model in ATMOSPHERIC_MODELS ||
        throw(ArgumentError("Unknown atmospheric_model: $atmospheric_model"))
    haskey(HEALTH_RESPONSE_COLUMNS, health_response) ||
        throw(ArgumentError("Unknown health_response: $health_response"))

    mortality_path = joinpath(
        momm_root,
        "input",
        "BenMAP",
        "Country Results Interpolated 2020-2100 by Model.csv"
    )

    country_path = joinpath(
        momm_root,
        "input",
        "Final Country Grid Col_Row Index.csv"
    )

    isfile(mortality_path) ||
        error("Missing MOMM-RFT mortality file: $mortality_path")

    isfile(country_path) ||
        error("Missing MOMM-RFT country crosswalk: $country_path")

    mortality = DataFrame(load(mortality_path))
    countries = DataFrame(load(country_path))

    # Select the stored response directly; no beta rescaling or new distribution.
    mortality = filter(
        row -> String(row.Model) == atmospheric_model,
        mortality
    )

    mortality.LocID = Int.(mortality.column)

    mortality.reference_deaths =
        Float64.(mortality[!, HEALTH_RESPONSE_COLUMNS[health_response]])

    nrow(mortality) > 0 || error("No rows for atmospheric_model=$atmospheric_model")
    mortality.atmospheric_model = fill(atmospheric_model, nrow(mortality))
    mortality.health_response = fill(health_response, nrow(mortality))

    countries.LocID = Int.(countries.COL)

    crosswalk = select(
        countries,
        :LocID,
        :COUNTRY,
        :RFF_iso_code,
        :Region,
        :SuperRegion
    )

    reference = leftjoin(
        mortality,
        crosswalk,
        on = :LocID
    )

    rename!(
        reference,
        :ModelYear => :year,
        :RFF_iso_code => :iso3,
        :COUNTRY => :country
    )

    reference.iso3 = [
        ismissing(x) ? missing : String(x)
        for x in reference.iso3
    ]

    sort!(
        reference,
        [:LocID, :year]
    )

    return reference
end

# ================================================================
# Original MOMM-RFT reference methane perturbation in ppb
# ================================================================

function reference_methane_delta_ppb(year::Int)

    if year < REFERENCE_PULSE_YEAR
        return 0.0
    end

    initial_delta_ppb =
        REFERENCE_PULSE_MT / METHANE_MT_PER_PPB

    return initial_delta_ppb *
           exp(
               -(year - REFERENCE_PULSE_YEAR) /
               REFERENCE_METHANE_LIFETIME
           )
end

# ================================================================
# Legacy MOMM-RFT user-pulse scaling
#
# Validation function only.
# ================================================================

function legacy_methane_scaling(
    years;
    pulse_year::Int,
    pulse_size_mt::Float64
)

    scale = zeros(Float64, length(years))

    initial_user_delta_ppb =
        pulse_size_mt / METHANE_MT_PER_PPB

    for (i, year) in enumerate(years)

        year_int = Int(year)

        if year_int < pulse_year
            scale[i] = 0.0
            continue
        end

        user_delta_ppb =
            initial_user_delta_ppb *
            exp(
                -(year_int - pulse_year) /
                REFERENCE_METHANE_LIFETIME
            )

        reference_delta_ppb =
            reference_methane_delta_ppb(year_int)

        scale[i] =
            user_delta_ppb /
            reference_delta_ppb
    end

    return scale
end

# ================================================================
# GIVE/FaIR methane scaling
#
# Converts the atmospheric CH4 perturbation produced directly by
# GIVE/FaIR into the scaling factor required to rescale the original
# McDuffie BenMAP mortality response.
#
# delta_ch4_ppb must therefore be:
#
#   CH4_modified - CH4_baseline
#
# from GIVE's :ch4_cycle, :CH₄ variable.
# ================================================================

function give_methane_scaling(
    years,
    delta_ch4_ppb
)

    length(years) == length(delta_ch4_ppb) ||
        error("years and delta_ch4_ppb must have identical lengths.")

    scales = zeros(Float64, length(years))

    for i in eachindex(years)

        year = Int(years[i])

        reference_delta =
            reference_methane_delta_ppb(year)

        if reference_delta == 0.0
            scales[i] = 0.0
        else
            scales[i] =
                Float64(delta_ch4_ppb[i]) /
                reference_delta
        end
    end

    return scales
end

# ================================================================
# Calculate country x year ozone respiratory mortality
#
# This function is deliberately agnostic about the atmospheric
# methane model.
#
# methane_scale_by_year may come from:
#   - legacy MOMM-RFT exponential decay
#   - GIVE/FaIR
# ================================================================

function calculate_ozone_deaths(
    reference::DataFrame,
    methane_scale_by_year::Dict{Int, Float64}
)

    result = select(
        reference,
        :year,
        :LocID,
        :iso3,
        :country,
        :Region,
        :SuperRegion,
        :reference_deaths
    )

    # Carry scientific case labels without changing the numerical calculation.
    for name in (:atmospheric_model, :health_response)
        if name in propertynames(reference)
            result[!, name] = copy(reference[!, name])
        end
    end

    result.methane_scale = [
        get(
            methane_scale_by_year,
            Int(year),
            0.0
        )
        for year in result.year
    ]

    result.ozone_respiratory_deaths =
        result.reference_deaths .*
        result.methane_scale

    return result
end

function calculate_ozone_deaths(
    reference::DataFrame,
    years,
    scales
)

    length(years) == length(scales) ||
        error("years and scales must have identical lengths.")

    scaling = Dict(
        Int(years[i]) => Float64(scales[i])
        for i in eachindex(years)
    )

    return calculate_ozone_deaths(
        reference,
        scaling
    )
end

# ================================================================
# Aggregate deaths geographically
# ================================================================

function aggregate_geography(
    results::DataFrame,
    geography::String
)

    if geography == "globe"

        subset = results

    elseif geography == "EU27"

        subset = filter(
            row ->
                !ismissing(row.iso3) &&
                row.iso3 in EU27,
            results
        )

    else

        subset = filter(
            row ->
                !ismissing(row.iso3) &&
                row.iso3 == geography,
            results
        )
    end

    annual = combine(
        groupby(subset, :year),

        :ozone_respiratory_deaths =>
            sum =>
            :ozone_respiratory_deaths
    )

    sort!(annual, :year)

    return annual
end

end