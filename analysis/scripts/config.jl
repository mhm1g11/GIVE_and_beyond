include(joinpath(@__DIR__, "..", "..", "scripts", "ScenarioConfig.jl"))
using .ScenarioConfig
const RELEASE_CONFIG = config_from_args()
ENV["MIMIGIVE_LABOR_DATA"] = RELEASE_CONFIG.labor_root
const GAS = :CH4
const POLICY_N_TRIALS = RELEASE_CONFIG.trials
const START_YEAR = RELEASE_CONFIG.valuation_year
const END_YEAR = 2050
const PULSE_YEARS = [2025,2030,2035,2040,2045,2050]
const IMPACT_HORIZON = 2100
const FULL_MODEL_HORIZON = 2300
const INCLUDE_LABOR = true
const LABOR_RESPONSES = (:ISO,:Lancet)
const PULSE_SIZE_MT = 1.0
const PRTP = exp(0.001972641)-1
const ETA = 1.244458999
const DISCOUNT_LABEL = "Ramsey"
const DISCOUNT_RATES = [(label=DISCOUNT_LABEL,prtp=PRTP,eta=ETA,ew=nothing,ew_norm_region=nothing)]
const EU27 = ["AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD","POL","PRT","ROU","SVK","SVN","ESP","SWE"]
const GERMANY = "DEU"
