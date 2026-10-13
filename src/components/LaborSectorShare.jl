using Mimi

# Agriculture share component

@defcomp LaborSectorShare begin

    # Parameters
    ypc2017 = Parameter(index=[country], unit="US\$2005/yr/person")
    gdp = Parameter(index=[time, country], unit="billion US\$2005/yr")
    population = Parameter(index=[time, country], unit = "million")

    agrish0 = Parameter(index=[country]) # initial share in 2017
    agel = Parameter(default = 0.31) # elasticity (FUND)

    # Variables
    agrish = Variable(index=[time,country]) # agricultural share of the economy

    function run_timestep(p,v,d,t)
        for c in d.country

            ypc = p.gdp[t, c] / p.population[t, c] * 1000.0
            v.agrish[t, c] = p.agrish0[c] * (ypc / p.ypc2017[c])^(-p.agel)

        end
    end
end
