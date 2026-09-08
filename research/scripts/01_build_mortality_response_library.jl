using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames

include(joinpath(@__DIR__, "config.jl"))

# ================================================================
# Output files
# ================================================================

const RESPONSE_PATH = joinpath(
    OUTPUT_DIR,
    "mortality_response_library.csv"
)

const CUMULATIVE_PATH = joinpath(
    OUTPUT_DIR,
    "mortality_cumulative_library.csv"
)

mkpath(OUTPUT_DIR)

# ================================================================
# Build mortality response for one methane pulse year
# ================================================================

function mortality_response_for_pulse(pulse_year::Int)

    println()
    println("Pulse year: ", pulse_year)
    println("Building models...")

    m = MimiGIVE.get_model()

    mm = MimiGIVE.get_marginal_model(
        m;
        year = pulse_year,
        gas = GAS,
        pulse_size = PULSE_SIZE_MT
    )

    println("Running GIVE...")
    run(mm)

    years = collect(Mimi.dim_keys(mm.base, :time))
    countries = string.(Mimi.dim_keys(mm.base, :country))

    # ------------------------------------------------------------
    # Check geography
    # ------------------------------------------------------------

    GERMANY in countries ||
        error("Germany ($GERMANY) not found in country dimension.")

    missing_eu = setdiff(EU27, countries)

    isempty(missing_eu) ||
        error("EU27 countries missing from GIVE: $missing_eu")

    germany_idx = findfirst(==(GERMANY), countries)
    eu27_idx = findall(c -> c in EU27, countries)

    # ------------------------------------------------------------
    # Physical mortality
    #
    # excess_deaths:
    # time × country
    # unit: persons
    # ------------------------------------------------------------

    deaths_base =
        mm.base[:CromarMortality, :excess_deaths]

    deaths_pulse =
        mm.modified[:CromarMortality, :excess_deaths]

    marginal_deaths =
        deaths_pulse .- deaths_base

    # Keep only impacts from the pulse year through the chosen
    # physical impact horizon.
    impact_idx = findall(
        y -> pulse_year <= y <= IMPACT_HORIZON,
        years
    )

    impact_years = years[impact_idx]

    # ------------------------------------------------------------
    # Annual mortality response by geography
    # ------------------------------------------------------------

    global_annual = vec(
        sum(
            marginal_deaths[impact_idx, :],
            dims = 2
        )
    )

    eu27_annual = vec(
        sum(
            marginal_deaths[impact_idx, eu27_idx],
            dims = 2
        )
    )

    germany_annual =
        marginal_deaths[impact_idx, germany_idx]

    # ------------------------------------------------------------
    # Convert response from the model pulse to per tonne CH4
    #
    # PULSE_SIZE_MT = 1.0 means 1 Mt CH4
    # 1 Mt = 1,000,000 tonnes
    # ------------------------------------------------------------

    pulse_size_t =
        PULSE_SIZE_MT * 1_000_000.0

    global_per_t =
        global_annual ./ pulse_size_t

    eu27_per_t =
        eu27_annual ./ pulse_size_t

    germany_per_t =
        germany_annual ./ pulse_size_t

    # ------------------------------------------------------------
    # Detailed annual response table
    # ------------------------------------------------------------

    response = DataFrame(
        pulse_year = Int[],
        impact_year = Int[],
        geography = String[],
        deaths_per_t_ch4 = Float64[]
    )

    for i in eachindex(impact_years)

        push!(
            response,
            (
                pulse_year,
                impact_years[i],
                "globe",
                global_per_t[i]
            )
        )

        push!(
            response,
            (
                pulse_year,
                impact_years[i],
                "EU27",
                eu27_per_t[i]
            )
        )

        push!(
            response,
            (
                pulse_year,
                impact_years[i],
                GERMANY,
                germany_per_t[i]
            )
        )
    end

    # ------------------------------------------------------------
    # Cumulative effect through impact horizon
    # ------------------------------------------------------------

    cumulative = DataFrame(
        pulse_year = [
            pulse_year,
            pulse_year,
            pulse_year
        ],

        geography = [
            "globe",
            "EU27",
            GERMANY
        ],

        impact_horizon = [
            IMPACT_HORIZON,
            IMPACT_HORIZON,
            IMPACT_HORIZON
        ],

        cumulative_deaths_per_t_ch4 = [
            sum(global_per_t),
            sum(eu27_per_t),
            sum(germany_per_t)
        ],

        cumulative_deaths_per_mt_ch4 = [
            sum(global_per_t) * 1_000_000,
            sum(eu27_per_t) * 1_000_000,
            sum(germany_per_t) * 1_000_000
        ]
    )

    return response, cumulative
end

# ================================================================
# Run all pulse years
# ================================================================

println("BUILDING GIVE PHYSICAL MORTALITY RESPONSE LIBRARY")
println("=================================================")
println()
println("Gas:             ", GAS)
println("Pulse years:     ", first(PULSE_YEARS), " to ", last(PULSE_YEARS))
println("Impact horizon:  ", IMPACT_HORIZON)
println("Pulse size:      ", PULSE_SIZE_MT, " Mt CH4")

all_responses = DataFrame(
    pulse_year = Int[],
    impact_year = Int[],
    geography = String[],
    deaths_per_t_ch4 = Float64[]
)

all_cumulative = DataFrame(
    pulse_year = Int[],
    geography = String[],
    impact_horizon = Int[],
    cumulative_deaths_per_t_ch4 = Float64[],
    cumulative_deaths_per_mt_ch4 = Float64[]
)

for pulse_year in PULSE_YEARS

    response, cumulative =
        mortality_response_for_pulse(pulse_year)

    append!(all_responses, response)
    append!(all_cumulative, cumulative)

    # The marginal models are relatively large.
    # Encourage Julia to release objects from the completed run.
    GC.gc()
end

# ================================================================
# Sort and save
# ================================================================

sort!(
    all_responses,
    [:pulse_year, :impact_year, :geography]
)

sort!(
    all_cumulative,
    [:pulse_year, :geography]
)

save(
    RESPONSE_PATH,
    all_responses
)

save(
    CUMULATIVE_PATH,
    all_cumulative
)

# ================================================================
# QA output
# ================================================================

println()
println("MORTALITY RESPONSE LIBRARY COMPLETE")
println("===================================")
println()
println("Annual response rows: ", nrow(all_responses))
println("Cumulative rows:      ", nrow(all_cumulative))
println()
println("Saved:")
println("  ", RESPONSE_PATH)
println("  ", CUMULATIVE_PATH)

println()
println(
    "CUMULATIVE NET TEMPERATURE-RELATED MORTALITY",
    " THROUGH ",
    IMPACT_HORIZON
)
println("===================================================")

for pulse_year in PULSE_YEARS

    println()
    println("Methane avoided in ", pulse_year)

    subset = filter(
        row -> row.pulse_year == pulse_year,
        all_cumulative
    )

    for row in eachrow(subset)
        println(
            "  ",
            rpad(row.geography, 6),
            ": ",
            row.cumulative_deaths_per_mt_ch4,
            " deaths / Mt CH4"
        )
    end
end

println()
println("Interpretation:")
println(
    "Positive values are additional deaths caused by emitting CH4."
)
println(
    "For avoided methane emissions, the same positive value is interpreted as deaths avoided."
)