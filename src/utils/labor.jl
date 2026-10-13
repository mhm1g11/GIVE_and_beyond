# Moore et al. (2026), v1.0.1. See provenance/labour_provenance.json and docs/DATA.md.
labor_data_dir() = get(ENV, "MIMIGIVE_LABOR_DATA", joinpath(@__DIR__, "..", "..", "data", "moore2026_labor"))

function labor_linear_interpolate(values, domain, x)
    itp = extrapolate(interpolate((domain,), values, Gridded(Linear())), Line())
    return itp(convert(Float64, x))
end

"""Load published labour tables in explicit GIVE country/model order. No crop damages."""
function labor_inputs(countries, response::Symbol; baseline_trial::Int=6546, ypc2017=nothing)
    response in (:ISO, :Lancet) || throw(ArgumentError("labor_response must be :ISO or :Lancet"))
    crosswalk = DataFrame(load(joinpath(labor_data_dir(), "region_crosswalk.csv")))
    shares = DataFrame(load(joinpath(labor_data_dir(), "202505_SectorShare_v2.csv")))
    gcms = String.(DataFrame(load(joinpath(labor_data_dir(), "dimension_gcm.csv"))).GCM)
    length(gcms) == 16 && gcms[1] == "model_ensemble" || error("Invalid labour model dimension")
    mapping = Dict(String(r.iso3) => String(r.gtap) for r in eachrow(crosswalk))
    sharemap = Dict(String(r.gtap) => Float64(r.agriculture) for r in eachrow(shares))
    agrish0 = [sharemap[mapping[c]] for c in countries]
    all(x -> isfinite(x) && 0 < x < 1, agrish0) || error("Invalid initial labour sector shares")
    if isnothing(ypc2017)
        base = DataFrame(load(joinpath(labor_data_dir(), "ypc2017", "rffsp_ypc2017_selected.csv")))
        base = base[base.trial .== baseline_trial, :]
        nrow(base) == length(countries) || error("2017 income baseline $baseline_trial not extracted; supply labor_ypc2017 in country order, USD2005")
        vals = Dict(String(r.iso3) => Float64(r.ypc2017_usd2011) * pricelevel_2011_to_2005 for r in eachrow(base))
        ypc2017 = [vals[c] for c in countries]
    end
    length(ypc2017) == length(countries) && all(x -> isfinite(x) && x > 0, ypc2017) || error("Invalid labour income baseline")
    df = DataFrame(load(joinpath(labor_data_dir(), "gtap_output", "20260428_Plants_People_results_v4_$(response)_Revision.csv")))
    df = df[df.Scenario .== "Labor Only (All Sectors)", :]
    rows = Dict((String(r.Country), Float64(r.Degrees), String(r.GCM)) => r for r in eachrow(df))
    length(rows) == nrow(df) || error("Duplicate labour table keys")
    ag = Array{Float64}(undef, length(countries), 7, 16)
    nonag = similar(ag)
    for (i,c) in enumerate(countries), (j,t) in enumerate(1.:0.5:4.), (k,g) in enumerate(gcms)
        r = rows[(mapping[c], t, g)]
        ag[i,j,k] = r.ST_AG_Welfare_in_M_USD / (r.Initial_Income_in_M_USD * agrish0[i])
        nonag[i,j,k] = r.ST_NONAG_Welfare_in_M_USD / (r.Initial_Income_in_M_USD * (1-agrish0[i]))
    end
    all(isfinite, ag) && all(isfinite, nonag) || error("Nonfinite labour response")
    return (; gcms, agrish0, ypc2017=Float64.(ypc2017), ag, nonag)
end

"""Register explicit labour IDs without consuming the global RNG. Call after get_mcs.
The 15 response models are independent of FaIR parameter sets. Ensemble ID 1 is
reserved for deterministic use; Monte Carlo IDs must lie in 2:16.
"""
function add_labor_draws!(mcs, model_ids::AbstractVector{<:Integer})
    length(model_ids) >= 2 || error("At least two labour draws are required")
    all(i -> 2 <= i <= 16, model_ids) || error("Labour MC model IDs must lie in 2:16")
    Mimi.add_RV!(mcs, :labor_model_id, Mimi.SampleStore(Int.(model_ids)))
    Mimi.add_transform!(mcs, :Labor, :gcm, :(=), :labor_model_id)
    return mcs
end

function load_labor_trial_design(path, original_path)
    df = DataFrame(load(path)); original = DataFrame(load(original_path))
    nrow(df) == nrow(original) || error("Labour design length mismatch")
    for col in (:trialnum, :rffsp_id, :fair_parameter_set_id)
        df[!,col] == original[!,col] || error("Labour design changed $col identities")
    end
    gcms = String.(DataFrame(load(joinpath(labor_data_dir(), "dimension_gcm.csv"))).GCM)
    all(i -> 2 <= i <= 16, df.labor_model_id) || error("Invalid labour identity")
    gcms[df.labor_model_id] == df.labor_model || error("Labour labels do not match IDs")
    return df
end


"""Opt-in labour channel. Existing agriculture and CIAM architecture are preserved.
The income baseline is fixed at construction, as in the published wrapper.
"""
function add_labor!(m; response::Symbol, baseline_trial::Int=6546, ypc2017=nothing, model_id::Int=1)
    Mimi.has_comp(m,:Labor) && error("Labour is already present")
    1 <= model_id <= 16 || error("Invalid labour model ID")
    countries = String.(dim_keys(m,:country))
    inp = labor_inputs(countries,response;baseline_trial=baseline_trial,ypc2017=ypc2017)
    set_dimension!(m,:gcm,inp.gcms)
    add_comp!(m,LaborSectorShare,:LaborSectorShare,before=:DamageAggregator,first=2020)
    add_comp!(m,Labor,:Labor,after=:LaborSectorShare,first=2020)
    for (p,v) in [(:ypc2017,inp.ypc2017),(:agrish0,inp.agrish0)]
        update_param!(m,:LaborSectorShare,p,v)
    end
    for comp in (:LaborSectorShare,:Labor)
        connect_param!(m,comp=>:gdp,:Socioeconomic=>:gdp)
        connect_param!(m,comp=>:population,:Socioeconomic=>:population)
    end
    connect_param!(m,:Labor=>:agrish,:LaborSectorShare=>:agrish)
    connect_param!(m,:Labor=>:temp,:temperature=>:T)
    update_param!(m,:Labor,:gtap_ag_impacts,inp.ag)
    update_param!(m,:Labor,:gtap_nonag_impacts,inp.nonag)
    update_param!(m,:Labor,:gcm,model_id)
    replace!(m,:DamageAggregator=>LaborDamageAggregator)
    Mimi.set_first_last!(m,:DamageAggregator,first=2020)
    connect_param!(m,:DamageAggregator=>:damage_labor,:Labor=>:laborcost)
    regions=String.(dim_keys(m,:fund_regions))
    # Use GIVE's authoritative mapping, not the paper's region naming conventions.
    own=DataFrame(load(joinpath(@__DIR__,"../../data/Mapping_countries_to_fund_regions.csv")))
    lookup=Dict(String(r.ISO3)=>String(r.fundregion) for r in eachrow(own))
    update_param!(m,:DamageAggregator,:labor_fund_mapping,[findfirst(==(lookup[c]),regions) for c in countries])
    return m
end
