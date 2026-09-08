using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics

include(joinpath(@__DIR__, "config.jl"))

const MOMM_SOCIO_PATH = joinpath(
    OUTPUT_DIR,
    "momm_reference_socioeconomics.csv"
)

const OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "give_momm_socioeconomic_scaling.csv"
)

println("BUILDING GIVE-FIRST SOCIOECONOMIC SCALING")
println("==========================================")
println()

# ================================================================
# Load McDuffie reference socioeconomic denominators
# ================================================================

momm =
    DataFrame(load(MOMM_SOCIO_PATH))

# ================================================================
# Load GIVE socioeconomic trajectories
# ================================================================

m =
    MimiGIVE.get_model()

run(m)

give_years =
    collect(dim_keys(m, :time))

give_countries =
    collect(dim_keys(m, :country))

give_population =
    m[:Socioeconomic, :population]

give_deathrate =
    m[:Socioeconomic, :deathrate]

year_index =
    Dict(
        Int(year) => i
        for (i, year) in enumerate(give_years)
    )

country_index =
    Dict(
        string(country) => i
        for (i, country) in enumerate(give_countries)
    )

# ================================================================
# Construct country x year scaling table
#
# Final physical scaling:
#
#   population_scale
#       = GIVE population / McDuffie reference population
#
#   mortality_scale
#       = GIVE all-cause mortality / McDuffie reference
#         all-cause mortality
#
#   socioeconomic_scale
#       = population_scale * mortality_scale
#
# This assumes that McDuffie's respiratory-to-all-cause mortality
# relationship remains fixed while the dynamic socioeconomic
# trajectory comes from GIVE.
# ================================================================

scaling = DataFrame(
    iso3 = String[],
    country = String[],
    year = Int[],
    give_population_millions = Float64[],
    momm_population_millions = Float64[],
    population_scale = Float64[],
    give_allcause_mortality_rate = Float64[],
    momm_allcause_mortality_rate = Float64[],
    mortality_scale = Float64[],
    socioeconomic_scale = Float64[],
    give_match = Bool[]
)

for row in eachrow(momm)

    if ismissing(row.iso3)
        continue
    end

    iso3 =
        string(row.iso3)

    year =
        Int(row.year)

    country =
        ismissing(row.country) ?
        "" :
        string(row.country)

    # McDuffie reference values
    momm_pop_m =
        Float64(
            row.reference_population_thousands
        ) / 1000

    momm_mort =
        Float64(
            row.reference_allcause_mortality_rate
        )

    # Default:
    # if GIVE does not contain the country/year, retain the
    # McDuffie reference socioeconomic level, i.e. scale = 1.
    give_pop_m =
        momm_pop_m

    give_mort =
        momm_mort

    pop_scale =
        1.0

    mort_scale =
        1.0

    matched =
        haskey(country_index, iso3) &&
        haskey(year_index, year)

    if matched

        ci =
            country_index[iso3]

        yi =
            year_index[year]

        raw_pop =
            give_population[yi, ci]

        raw_mort =
            give_deathrate[yi, ci]

        if !ismissing(raw_pop) &&
           !ismissing(raw_mort) &&
           momm_pop_m > 0 &&
           momm_mort > 0

            # GIVE population is in millions.
            give_pop_m =
                Float64(raw_pop)

            # GIVE deathrate is deaths per 1,000 population.
            # Convert to probability/rate per person.
            give_mort =
                Float64(raw_mort) / 1000

            pop_scale =
                give_pop_m / momm_pop_m

            mort_scale =
                give_mort / momm_mort

        else
            matched = false
        end
    end

    push!(
        scaling,
        (
            iso3,
            country,
            year,
            give_pop_m,
            momm_pop_m,
            pop_scale,
            give_mort,
            momm_mort,
            mort_scale,
            pop_scale * mort_scale,
            matched
        )
    )
end

sort!(
    scaling,
    [:iso3, :year]
)

save(
    OUTPUT_PATH,
    scaling
)

# ================================================================
# QA
# ================================================================

println("Coverage")
println("========")
println()

n_total =
    nrow(scaling)

n_matched =
    count(scaling.give_match)

println(
    "Country-year rows: ",
    n_total
)

println(
    "Matched to GIVE: ",
    n_matched,
    " (",
    round(
        100 * n_matched / n_total,
        digits = 2
    ),
    "%)"
)

println()
println("Germany")
println("=======")
println()

println(
    "year | population scale | mortality scale | combined scale"
)

for year in [2025, 2030, 2050, 2100]

    row = filter(
        r ->
            r.iso3 == "DEU" &&
            r.year == year,
        scaling
    )

    nrow(row) == 1 ||
        error(
            "Expected one Germany row for $year."
        )

    println(
        year,
        " | ",
        round(
            row.population_scale[1],
            digits = 4
        ),
        " | ",
        round(
            row.mortality_scale[1],
            digits = 4
        ),
        " | ",
        round(
            row.socioeconomic_scale[1],
            digits = 4
        )
    )
end

println()
println("Scaling distribution for GIVE-matched rows")
println("===========================================")
println()

matched_scaling =
    scaling[
        scaling.give_match,
        :
    ]

println(
    "Median: ",
    median(
        matched_scaling.socioeconomic_scale
    )
)

println(
    "5th percentile: ",
    quantile(
        matched_scaling.socioeconomic_scale,
        0.05
    )
)

println(
    "95th percentile: ",
    quantile(
        matched_scaling.socioeconomic_scale,
        0.95
    )
)

println()
println("Saved:")
println("  ", OUTPUT_PATH)