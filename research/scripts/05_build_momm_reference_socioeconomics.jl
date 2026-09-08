using FileIO
using CSVFiles
using DataFrames
using Statistics
using Mimi
using MimiGIVE

include(joinpath(@__DIR__, "config.jl"))

const MOMM_ROOT = normpath(
    joinpath(
        @__DIR__,
        "..",
        "external",
        "MOMM-RFT"
    )
)

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

const OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "momm_reference_socioeconomics.csv"
)

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
# Compare Germany with GIVE
# ================================================================

m = MimiGIVE.get_model()
run(m)

give_years =
    collect(dim_keys(m, :time))

give_countries =
    collect(dim_keys(m, :country))

give_deathrate =
    m[:Socioeconomic, :deathrate]

give_population =
    m[:Socioeconomic, :population]

deu_idx =
    findfirst(==("DEU"), give_countries)

println("GERMANY COMPARISON")
println("==================")
println()

println(
    "year | GIVE pop m | MOMM pop m | pop ratio | " *
    "GIVE mortality | MOMM mortality | mortality ratio"
)

for year in [2025, 2030, 2050, 2100]

    give_year_idx =
        findfirst(==(year), give_years)

    momm_row = filter(
        row ->
            row.iso3 == "DEU" &&
            row.year == year,
        annual
    )

    nrow(momm_row) == 1 ||
        error(
            "Expected exactly one MOMM Germany row for $year."
        )

    # GIVE population appears in millions.
    give_pop_m =
        Float64(
            give_population[
                give_year_idx,
                deu_idx
            ]
        )

    # MOMM reference population is thousands.
    momm_pop_m =
        Float64(
            momm_row.reference_population_thousands[1]
        ) / 1000

    # GIVE deathrate is expressed per 1,000 people.
    # Convert to per-person mortality rate.
    give_mort =
        Float64(
            give_deathrate[
                give_year_idx,
                deu_idx
            ]
        ) / 1000

    momm_mort =
        Float64(
            momm_row.reference_allcause_mortality_rate[1]
        )

    println(
        year, " | ",
        round(give_pop_m, digits = 3), " | ",
        round(momm_pop_m, digits = 3), " | ",
        round(give_pop_m / momm_pop_m, digits = 4), " | ",
        round(give_mort, digits = 6), " | ",
        round(momm_mort, digits = 6), " | ",
        round(give_mort / momm_mort, digits = 4)
    )
end

println()
println("Saved:")
println("  ", OUTPUT_PATH)