using Mimi
using MimiGIVE

m = MimiGIVE.get_model()
run(m)

md = Mimi.modeldef(m)

println("GIVE HEALTH / SOCIOECONOMIC INPUT INSPECTION")
println("============================================")
println()

components = collect(keys(md.namespace))

println("ALL COMPONENTS")
println("==============")

for component in components
    println(component)
end

println()
println("RELEVANT VARIABLES AND PARAMETERS")
println("=================================")

keywords = [
    "pop",
    "gdp",
    "income",
    "consum",
    "vsl",
    "mort",
    "death",
    "resp",
    "life"
]

for component in components

    vars = try
        Mimi.variable_names(md, component)
    catch
        Symbol[]
    end

    pars = try
        Mimi.parameter_names(md, component)
    catch
        Symbol[]
    end

    matched_vars = filter(vars) do name
        text = lowercase(String(name))
        any(keyword -> occursin(keyword, text), keywords)
    end

    matched_pars = filter(pars) do name
        text = lowercase(String(name))
        any(keyword -> occursin(keyword, text), keywords)
    end

    if !isempty(matched_vars) || !isempty(matched_pars)

        println()
        println("COMPONENT: ", component)

        if !isempty(matched_vars)
            println("  Variables:")
            for variable in matched_vars
                println("    ", variable)
            end
        end

        if !isempty(matched_pars)
            println("  Parameters:")
            for parameter in matched_pars
                println("    ", parameter)
            end
        end
    end
end

println()
println("FULL CROMAR MORTALITY COMPONENT")
println("==============================")

if :CromarMortality in components

    println()
    println("Variables:")

    for variable in Mimi.variable_names(md, :CromarMortality)
        println("  ", variable)
    end

    println()
    println("Parameters:")

    for parameter in Mimi.parameter_names(md, :CromarMortality)
        println("  ", parameter)
    end

else
    println("CromarMortality component not found.")
end