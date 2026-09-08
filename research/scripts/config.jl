# ================================================================
# GIVE methane regulation research configuration
# ================================================================

# Greenhouse gas
const GAS = :CH4

# Proof-of-concept policy / pulse years
const START_YEAR = 2025
const END_YEAR = 2031
const PULSE_YEARS = collect(START_YEAR:END_YEAR)

# Main impact horizon
const IMPACT_HORIZON = 2100

# Full GIVE horizon, retained for sensitivity analysis later
const FULL_MODEL_HORIZON = 2300

# Standard GIVE methane pulse
# 1.0 = 1 Mt CH4
const PULSE_SIZE_MT = 1.0

# Ramsey discounting assumptions
const PRTP = 0.015
const ETA = 1.45
const DISCOUNT_LABEL = "Ramsey"

const DISCOUNT_RATES = [
    (
        label = DISCOUNT_LABEL,
        prtp = PRTP,
        eta = ETA,
        ew = nothing,
        ew_norm_region = nothing
    )
]

# EU27 ISO3 codes
const EU27 = [
    "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK",
    "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL",
    "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL",
    "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"
]

const GERMANY = "DEU"

# Research directories
const RESEARCH_DIR = normpath(joinpath(@__DIR__, ".."))
const INPUT_DIR = joinpath(RESEARCH_DIR, "inputs")
const OUTPUT_DIR = joinpath(RESEARCH_DIR, "outputs")
const GIVE_RUN_DIR = joinpath(OUTPUT_DIR, "give_runs")
const POLICY_RESULT_DIR = joinpath(OUTPUT_DIR, "policy_results")