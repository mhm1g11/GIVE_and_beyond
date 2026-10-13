using Mimi

# Labor impacts component

@defcomp Labor begin

    gcm = Index() # 16 gcm indices, the first is the ensemble and the next 15 are individual GCMs

    # Parameters
    gdp = Parameter(index=[time, country], unit="billion US\$2005/yr")
    population = Parameter(index=[time, country], unit = "million")
    temp = Parameter(index=[time], unit="degC")
    gcm = Parameter{Int}(default = 1)
    agrish = Parameter(index=[time,country]) # agricultural share of the economy

    gtap_ag_impacts = Parameter(index=[country, 7, gcm])  # seven temperature data points per country 1:0.5:4
    gtap_nonag_impacts = Parameter(index=[country, 7, gcm]) # seven temperature data points per country 1:0.5:4

    # Variables
    temp_normalized = Variable(index = [time], unit="degC") # normalized temperature -- subtract 0.82 deg C to adjust for 1995-2015 basseline
    
    laborloss_ag_gtap_frac = Variable(index=[time, country]) # fractional loss - intermediate variable for calculating laborcost
    laborloss_nonag_gtap_frac = Variable(index=[time, country]) # fractional loss - intermediate variable for calculating laborcost

    laborcost_ag = Variable(index=[time, country], unit="billion US\$2005/yr")
    laborcost_nonag = Variable(index=[time, country], unit="billion US\$2005/yr")

    laborcost = Variable(index=[time, country], unit="billion US\$2005/yr")

    function run_timestep(p,v,d,t)

        v.temp_normalized[t] = p.temp[t] - 0.82

        for c in d.country

            # Interpolate using the seven gtap welfare points with the additional origin (0,0) point
            ag_impact = labor_linear_interpolate([0, p.gtap_ag_impacts[c, :, p.gcm]...], [0., collect(1:0.5:4)...], v.temp_normalized[t])
            v.laborloss_ag_gtap_frac[t, c] = -1 * ag_impact # take the negative to go from impact to loss

            nonag_impact = labor_linear_interpolate([0, p.gtap_nonag_impacts[c, :, p.gcm]...], [0., collect(1:0.5:4)...], v.temp_normalized[t])
            v.laborloss_nonag_gtap_frac[t, c] = -1 * nonag_impact # take the negative to go from impact to loss

            # Calculate total cost for the labor sector based on the fractional loss
            v.laborcost_nonag[t, c] = p.gdp[t, c] * (1-p.agrish[t, c]) * v.laborloss_nonag_gtap_frac[t, c]
            v.laborcost_ag[t, c] = p.gdp[t, c] * p.agrish[t, c] * v.laborloss_ag_gtap_frac[t, c]

            v.laborcost[t, c] = v.laborcost_nonag[t,c] + v.laborcost_ag[t, c]   
        end
    end
end
