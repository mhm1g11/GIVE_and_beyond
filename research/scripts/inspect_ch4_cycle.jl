using Mimi
using MimiGIVE

m = MimiGIVE.get_model()

println("CH4 VARIABLES:")
for name in Mimi.variable_names(m.md, :ch4_cycle)
    println(name)
end

println()
println("CH4 PARAMETERS:")
for name in Mimi.parameter_names(m.md, :ch4_cycle)
    println(name)
end