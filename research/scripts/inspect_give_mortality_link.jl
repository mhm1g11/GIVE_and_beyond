using Mimi
using MimiGIVE

m = MimiGIVE.get_model()
run(m)

years = collect(dim_keys(m, :time))
countries = collect(dim_keys(m, :country))

deathrate = m[:Socioeconomic, :deathrate]
baseline = m[:CromarMortality, :baseline_mortality_rate]
population = m[:Socioeconomic, :population]
cromar_population = m[:CromarMortality, :population]
vsl = m[:VSL, :vsl]
cromar_vsl = m[:CromarMortality, :vsl]

println("GIVE MORTALITY CONNECTION CHECK")
println("===============================")
println()

println(
    "Max |Socioeconomic deathrate - Cromar baseline mortality|: ",
    maximum(abs.(deathrate .- baseline))
)

println(
    "Max |Socioeconomic population - Cromar population|: ",
    maximum(abs.(population .- cromar_population))
)

println(
    "Max |VSL output - Cromar VSL|: ",
    maximum(abs.(vsl .- cromar_vsl))
)

deu_idx = findfirst(==("DEU"), countries)

println()
println("Germany examples")
println("================")

for year in [2025, 2030, 2050, 2100]

    year_idx = findfirst(==(year), years)

    println(
        year,
        " | deathrate = ", deathrate[year_idx, deu_idx],
        " | population = ", population[year_idx, deu_idx],
        " | VSL = ", vsl[year_idx, deu_idx]
    )
end