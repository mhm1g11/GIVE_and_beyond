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
        "..",
        "scripts",
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

const GIVE_LIBRARY_PATH = joinpath(
    OUTPUT_DIR,
    "ozone_mortality_cumulative_library.csv"
)

reference =
    load_momm_reference(MOMM_ROOT)

give_library =
    DataFrame(load(GIVE_LIBRARY_PATH))

println("OZONE PULSE-YEAR PATTERN CHECK")
println("==============================")
println()

println(
    "pulse | geography | McDuffie CH4 | GIVE/FaIR CH4 | GIVE/McDuffie"
)

for pulse_year in PULSE_YEARS

    years =
        collect(2020:IMPACT_HORIZON)

    legacy_scales =
        legacy_methane_scaling(
            years;
            pulse_year = pulse_year,
            pulse_size_mt = 1.0
        )

    legacy_results =
        calculate_ozone_deaths(
            reference,
            years,
            legacy_scales
        )

    for geography in ["globe", "EU27", "DEU"]

        legacy_annual =
            aggregate_geography(
                legacy_results,
                geography
            )

        legacy_total =
            sum(
                legacy_annual.ozone_respiratory_deaths
            )

        give_row =
            filter(
                row ->
                    row.pulse_year == pulse_year &&
                    String(row.geography) == geography,
                give_library
            )

        nrow(give_row) == 1 ||
            error(
                "Expected exactly one GIVE result for $pulse_year / $geography."
            )

        give_total =
            Float64(
                give_row.cumulative_deaths_per_mt_ch4[1]
            )

        println(
            pulse_year,
            " | ",
            rpad(geography, 6),
            " | ",
            round(legacy_total, digits = 3),
            " | ",
            round(give_total, digits = 3),
            " | ",
            round(
                give_total / legacy_total,
                digits = 4
            )
        )
    end
end