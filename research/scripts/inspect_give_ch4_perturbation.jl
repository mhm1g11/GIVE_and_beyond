using Mimi
using MimiGIVE

const PULSE_YEAR = 2025
const PULSE_SIZE_MT = 1.0

println("GIVE / FaIR CH4 PERTURBATION INSPECTION")
println("======================================")
println()

# Build baseline and marginal models
m = MimiGIVE.get_model()

mm = MimiGIVE.get_marginal_model(
    m;
    year = PULSE_YEAR,
    gas = :CH4,
    pulse_size = PULSE_SIZE_MT
)

run(mm)

# Model years
years = collect(dim_keys(mm.base, :time))

# Atmospheric methane concentration
ch4_base = mm.base[:ch4_cycle, :CH₄]
ch4_pulse = mm.modified[:ch4_cycle, :CH₄]

delta_ch4 = ch4_pulse .- ch4_base

println("Pulse year: ", PULSE_YEAR)
println("Pulse size: ", PULSE_SIZE_MT, " Mt CH4")
println()

println("Baseline CH4 in pulse year: ",
    ch4_base[findfirst(==(PULSE_YEAR), years)])

println("Marginal-model CH4 in pulse year: ",
    ch4_pulse[findfirst(==(PULSE_YEAR), years)])

println("Delta CH4 in pulse year: ",
    delta_ch4[findfirst(==(PULSE_YEAR), years)])

println()

# First year with a numerically non-zero perturbation
first_nonzero_idx = findfirst(x -> abs(x) > 1e-12, delta_ch4)

if first_nonzero_idx !== nothing
    println(
        "First non-zero CH4 perturbation: ",
        years[first_nonzero_idx],
        " -> ",
        delta_ch4[first_nonzero_idx]
    )
end

# Peak perturbation
peak_idx = argmax(delta_ch4)

println(
    "Peak CH4 perturbation: ",
    years[peak_idx],
    " -> ",
    delta_ch4[peak_idx]
)

println()
println("ANNUAL PATH")
println("===========")
println("year | baseline_CH4 | pulse_CH4 | delta_CH4")

for year in 2023:2040

    idx = findfirst(==(year), years)

    if idx !== nothing
        println(
            year, " | ",
            ch4_base[idx], " | ",
            ch4_pulse[idx], " | ",
            delta_ch4[idx]
        )
    end
end

println()

# Compare with the simple MOMM-RFT conversion:
# 1 Mt CH4 / 2.75 Mt per ppb = 0.363636... ppb
momm_initial_delta = PULSE_SIZE_MT / 2.75

give_initial_delta =
    delta_ch4[findfirst(==(PULSE_YEAR), years)]

println("INITIAL-PULSE COMPARISON")
println("========================")

println(
    "MOMM-RFT simple conversion for 1 Mt: ",
    momm_initial_delta,
    " ppb"
)

println(
    "GIVE/FaIR pulse-year perturbation: ",
    give_initial_delta
)

println(
    "GIVE / MOMM initial ratio: ",
    give_initial_delta / momm_initial_delta
)