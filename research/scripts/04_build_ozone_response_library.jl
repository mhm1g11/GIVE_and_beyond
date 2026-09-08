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

const ANNUAL_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_response_library.csv"
)

const CUMULATIVE_OUTPUT = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_cumulative_library.csv"
)

println("BUILDING GIVE-FIRST OZONE MORTALITY RESPONSE LIBRARY")
println("=====================================================")
println()

reference =
    load_momm_reference(MOMM_ROOT)

annual_rows = DataFrame(
    pulse_year = Int[],
    impact_year = Int[],
    geography = String[],
    deaths_per_t_ch4 = Float64[]
)

cumulative_rows = DataFrame(
    pulse_year = Int[],
    geography = String[],
    impact_horizon = Int[],
    cumulative_deaths_per_t_ch4 = Float64[],
    cumulative_deaths_per_mt_ch4 = Float64[]
)

for pulse_year in PULSE_YEARS

    println("Pulse year: ", pulse_year)

    # ============================================================
    # Build GIVE marginal model for a 1 Mt CH4 pulse
    # ============================================================

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
        collect(dim_keys(mm.base, :time))

    ch4_base =
        mm.base[:ch4_cycle, :CH₄]

    ch4_modified =
        mm.modified[:ch4_cycle, :CH₄]

    delta_ch4 =
        ch4_modified .- ch4_base

    # ============================================================
    # Restrict to MOMM-RFT health-response period
    # ============================================================

    years =
        collect(2020:IMPACT_HORIZON)

    indices = [
        findfirst(==(year), give_years)
        for year in years
    ]

    any(isnothing, indices) &&
        error(
            "At least one required year is missing from GIVE."
        )

    give_delta = [
        Float64(delta_ch4[idx])
        for idx in indices
    ]

    # ============================================================
    # Translate GIVE methane perturbation into McDuffie mortality
    # scaling
    # ============================================================

    scales =
        give_methane_scaling(
            years,
            give_delta
        )

    results =
        calculate_ozone_deaths(
            reference,
            years,
            scales
        )

    # ============================================================
    # Aggregate geography
    # ============================================================

    for geography in ["globe", "EU27", "DEU"]

        annual =
            aggregate_geography(
                results,
                geography
            )

        # The model pulse is 1 Mt CH4 = 1,000,000 tonnes.
        for row in eachrow(annual)

            push!(
                annual_rows,
                (
                    pulse_year,
                    Int(row.year),
                    geography,
                    Float64(
                        row.ozone_respiratory_deaths
                    ) / 1e6
                )
            )
        end

        cumulative_deaths =
            sum(
                annual.ozone_respiratory_deaths
            )

        push!(
            cumulative_rows,
            (
                pulse_year,
                geography,
                IMPACT_HORIZON,
                cumulative_deaths / 1e6,
                cumulative_deaths
            )
        )

        println(
            "  ",
            rpad(geography, 6),
            ": ",
            cumulative_deaths,
            " respiratory deaths / Mt CH4"
        )
    end

    println()
end

sort!(
    annual_rows,
    [:pulse_year, :geography, :impact_year]
)

sort!(
    cumulative_rows,
    [:pulse_year, :geography]
)

save(
    ANNUAL_OUTPUT,
    annual_rows
)

save(
    CUMULATIVE_OUTPUT,
    cumulative_rows
)

println("OZONE RESPONSE LIBRARY COMPLETE")
println("===============================")
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