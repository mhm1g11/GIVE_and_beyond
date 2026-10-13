using FileIO
using CSVFiles
using DataFrames
using Statistics

include(joinpath(@__DIR__, "config.jl"))

const MOMM_ROOT = RELEASE_CONFIG.momm_root

const MORT_PATH = joinpath(
    MOMM_ROOT,
    "input",
    "RFF",
    "lookup_tables",
    "rff_mort_means.csv"
)

const POP_PATH = joinpath(
    MOMM_ROOT,
    "input",
    "RFF",
    "lookup_tables",
    "rff_pop_means.csv"
)

const COUNTRY_PATH = joinpath(
    MOMM_ROOT,
    "input",
    "Final Country Grid Col_Row Index.csv"
)

const OUTPUT_PATH = RELEASE_CONFIG.momm_socio
ispath(OUTPUT_PATH) && error("Reference already exists: $OUTPUT_PATH")
mkpath(dirname(OUTPUT_PATH))

# ================================================================
# Simple linear interpolation
# ================================================================

function interpolate_value(
    xs::Vector{Int},
    ys::Vector{Float64},
    x::Int
)

    if x <= first(xs)
        return first(ys)
    end

    if x >= last(xs)
        return last(ys)
    end

    exact = findfirst(==(x), xs)

    if exact !== nothing
        return ys[exact]
    end

    upper = findfirst(v -> v > x, xs)
    lower = upper - 1

    x0 = xs[lower]
    x1 = xs[upper]

    y0 = ys[lower]
    y1 = ys[upper]

    weight =
        (x - x0) /
        (x1 - x0)

    return y0 + weight * (y1 - y0)
end

# ================================================================
# Load McDuffie reference data
# ================================================================

println("BUILDING MOMM REFERENCE SOCIOECONOMICS")
println("======================================")
println()

mort =
    DataFrame(load(MORT_PATH))

pop =
    DataFrame(load(POP_PATH))

countries =
    DataFrame(load(COUNTRY_PATH))

# ------------------------------------------------
# Convert mortality periods such as:
#
#   2020-2025
#   2025-2030
#
# to the start year used for population matching.
# ------------------------------------------------

mort.reference_year = [
    parse(
        Int,
        split(string(period), "-")[1]
    )
    for period in mort.Period
]

# ================================================================
# McDuffie mean all-cause mortality
#
# Exactly analogous to their respiratory mortality calculation,
# except WITHOUT multiplying by final_AF.
#
# This gives the all-cause mortality denominator that we need when
# replacing McDuffie's mortality trajectory with GIVE's.
# ================================================================

mort_for_join = select(
    mort,
    :LocID,
    :reference_year,
    :Age,
    :mean_mort_rate
)

pop_for_join = select(
    pop,
    :LocID,
    :Year,
    :Age,
    :mean_pop
)

rename!(
    pop_for_join,
    :Year => :reference_year
)

mort_pop = leftjoin(
    mort_for_join,
    pop_for_join,
    on = [:LocID, :reference_year, :Age]
)

dropmissing!(
    mort_pop,
    [:mean_mort_rate, :mean_pop]
)

mort_pop.weighted_mortality =
    Float64.(mort_pop.mean_mort_rate) .*
    Float64.(mort_pop.mean_pop)

mort_reference = combine(
    groupby(
        mort_pop,
        [:LocID, :reference_year]
    ),

    [:weighted_mortality, :mean_pop] =>
        ((wm, p) -> sum(wm) / sum(p)) =>
        :reference_allcause_mortality_rate
)

# ================================================================
# McDuffie mean population, all ages
#
# rff_pop_means is in thousands of persons.
# ================================================================

population_reference = combine(
    groupby(
        pop,
        [:LocID, :Year]
    ),

    :mean_pop =>
        (x -> sum(skipmissing(x))) =>
        :reference_population_thousands
)

rename!(
    population_reference,
    :Year => :reference_year
)

# ================================================================
# Interpolate both reference series annually
# ================================================================

annual = DataFrame(
    LocID = Int[],
    year = Int[],
    reference_population_thousands = Float64[],
    reference_allcause_mortality_rate = Float64[]
)

locids = intersect(
    unique(Int.(population_reference.LocID)),
    unique(Int.(mort_reference.LocID))
)

for locid in sort(locids)

    pop_sub = filter(
        row -> Int(row.LocID) == locid,
        population_reference
    )

    mort_sub = filter(
        row -> Int(row.LocID) == locid,
        mort_reference
    )

    sort!(pop_sub, :reference_year)
    sort!(mort_sub, :reference_year)

    pop_years =
        Int.(pop_sub.reference_year)

    pop_values =
        Float64.(pop_sub.reference_population_thousands)

    mort_years =
        Int.(mort_sub.reference_year)

    mort_values =
        Float64.(mort_sub.reference_allcause_mortality_rate)

    for year in 2020:2100

        push!(
            annual,
            (
                locid,
                year,
                interpolate_value(
                    pop_years,
                    pop_values,
                    year
                ),
                interpolate_value(
                    mort_years,
                    mort_values,
                    year
                )
            )
        )
    end
end

# ================================================================
# Add ISO3 codes
# ================================================================

crosswalk = select(
    countries,
    :COL,
    :RFF_iso_code,
    :COUNTRY
)

rename!(
    crosswalk,
    :COL => :LocID,
    :RFF_iso_code => :iso3,
    :COUNTRY => :country
)

annual = leftjoin(
    annual,
    crosswalk,
    on = :LocID
)

annual.iso3 = [
    ismissing(x) ? missing : string(x)
    for x in annual.iso3
]

sort!(
    annual,
    [:iso3, :year]
)

save(
    OUTPUT_PATH,
    annual
)

# ================================================================

println("Wrote reference denominators: ",OUTPUT_PATH)
