using Random
using StatsBase
using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)

# =====================================================================
# Configuration
# =====================================================================

const N_TRIALS = 5
const MC_SEED = 20260908

const TRIAL_DESIGN_PATH = joinpath(
    INPUT_DIR,
    "mc_trial_design.csv"
)

const CH4_DIAGNOSTIC_PATH = joinpath(
    OUTPUT_DIR,
    "ch4_pulse_mc_diagnostic.csv"
)

const CH4_DIAGNOSTIC_SUMMARY_PATH = joinpath(
    OUTPUT_DIR,
    "ch4_pulse_mc_diagnostic_summary.csv"
)

const BASE_MCS_DIR = joinpath(
    OUTPUT_DIR,
    "mc_diagnostic_ch4_base"
)

const MODIFIED_MCS_DIR = joinpath(
    OUTPUT_DIR,
    "mc_diagnostic_ch4_modified"
)

println("PREPARING EXPLICIT ALIGNED GIVE MONTE CARLO TRIALS")
println("==================================================")
println()

# =====================================================================
# 1. Create explicit trial design
#
# GIVE itself samples:
#
#   RFF socioeconomic scenario: 1:10,000
#   FaIR parameter set:         1:2,237
#
# We now choose these IDs explicitly and save them.
#
# This replaces our earlier proof-of-concept approach where alignment
# depended only on resetting the same random seed.
# =====================================================================

rng_rff =
    MersenneTwister(
        MC_SEED
    )

rng_fair =
    MersenneTwister(
        MC_SEED + 1
    )

rffsp_ids =
    sample(
        rng_rff,
        collect(1:10_000),
        N_TRIALS;
        replace = true
    )

fair_ids =
    sample(
        rng_fair,
        collect(1:2_237),
        N_TRIALS;
        replace = true
    )

trial_design = DataFrame(
    trialnum = collect(1:N_TRIALS),
    rffsp_id = rffsp_ids,
    fair_parameter_set_id = fair_ids
)

save(
    TRIAL_DESIGN_PATH,
    trial_design
)

println("Explicit trial design")
println("---------------------")

for row in eachrow(
    trial_design
)

    println(
        "Trial ",
        row.trialnum,
        ": RFF SP ",
        row.rffsp_id,
        " | FaIR ",
        row.fair_parameter_set_id
    )
end

println()
println(
    "Saved trial design:"
)

println(
    "  ",
    TRIAL_DESIGN_PATH
)

println()

# =====================================================================
# 2. Diagnostic: does the marginal atmospheric CH4 pulse differ
#    across GIVE Monte Carlo trials?
#
# This matters because:
#
# if the pulse response is identical:
#     ozone can use one common GIVE CH4 impulse response
#
# if it differs:
#     ozone must inherit the trial-specific CH4 response too
#
# We test a 1 Mt CH4 pulse in 2025.
# =====================================================================

const TEST_PULSE_YEAR = 2025

println("TESTING MONTE CARLO VARIATION IN ATMOSPHERIC CH4 PULSE")
println("=======================================================")
println()

println(
    "Test pulse: ",
    TEST_PULSE_YEAR,
    ", 1 Mt CH4"
)

println()

m =
    MimiGIVE.get_model()

mm =
    MimiGIVE.get_marginal_model(
        m;
        year = TEST_PULSE_YEAR,
        gas = :CH4,
        pulse_size = 1.0
    )

# Remove old diagnostic folders so reruns are clean.
if isdir(BASE_MCS_DIR)
    rm(
        BASE_MCS_DIR;
        recursive = true
    )
end

if isdir(MODIFIED_MCS_DIR)
    rm(
        MODIFIED_MCS_DIR;
        recursive = true
    )
end

# =====================================================================
# 3. Run baseline MCS with explicit RFF and FaIR IDs
# =====================================================================

println(
    "Running baseline CH4-cycle trials..."
)

Random.seed!(
    MC_SEED
)

base_results =
    MimiGIVE.run_mcs(
        trials = N_TRIALS,

        m = mm.base,

        fair_parameter_set = :deterministic,
        fair_parameter_set_ids = fair_ids,

        rffsp_sampling = :deterministic,
        rffsp_sampling_ids = rffsp_ids,

        save_list = [
            (
                :ch4_cycle,
                :CH₄
            )
        ],

        output_dir = BASE_MCS_DIR,

        results_in_memory = true
    )

# =====================================================================
# 4. Run marginal MCS with exactly the same explicit socioeconomic
#    and FaIR parameter sets
#
# Resetting the seed also keeps all other GIVE random draws aligned
# between the two runs.
# =====================================================================

println(
    "Running marginal CH4-cycle trials..."
)

Random.seed!(
    MC_SEED
)

modified_results =
    MimiGIVE.run_mcs(
        trials = N_TRIALS,

        m = mm.modified,

        fair_parameter_set = :deterministic,
        fair_parameter_set_ids = fair_ids,

        rffsp_sampling = :deterministic,
        rffsp_sampling_ids = rffsp_ids,

        save_list = [
            (
                :ch4_cycle,
                :CH₄
            )
        ],

        output_dir = MODIFIED_MCS_DIR,

        results_in_memory = true
    )

println()

# =====================================================================
# 5. Extract CH4 concentration trajectories
# =====================================================================

base_df =
    getdataframe(
        base_results,
        :ch4_cycle,
        :CH₄
    )

modified_df =
    getdataframe(
        modified_results,
        :ch4_cycle,
        :CH₄
    )

# =====================================================================
# Helper to identify Mimi output columns robustly
# =====================================================================

function find_column(
    df::DataFrame,
    candidates::Vector{Symbol}
)

    available =
        propertynames(df)

    for candidate in candidates

        if candidate in available
            return candidate
        end
    end

    error(
        "Could not find any of $(candidates) in dataframe. " *
        "Available columns are $(available)."
    )
end

trial_col_base =
    find_column(
        base_df,
        [
            :trialnum,
            :trial,
            :trial_number
        ]
    )

time_col_base =
    find_column(
        base_df,
        [
            :time,
            :year
        ]
    )

value_col_base =
    find_column(
        base_df,
        [
            Symbol("CH₄")
        ]
    )

trial_col_modified =
    find_column(
        modified_df,
        [
            :trialnum,
            :trial,
            :trial_number
        ]
    )

time_col_modified =
    find_column(
        modified_df,
        [
            :time,
            :year
        ]
    )

value_col_modified =
    find_column(
        modified_df,
        [
            Symbol("CH₄")
        ]
    )

base_clean = select(
    base_df,

    trial_col_base =>
        :trialnum,

    time_col_base =>
        :year,

    value_col_base =>
        :ch4_base_ppb
)

modified_clean = select(
    modified_df,

    trial_col_modified =>
        :trialnum,

    time_col_modified =>
        :year,

    value_col_modified =>
        :ch4_modified_ppb
)

base_clean.trialnum =
    Int.(
        base_clean.trialnum
    )

base_clean.year =
    Int.(
        base_clean.year
    )

modified_clean.trialnum =
    Int.(
        modified_clean.trialnum
    )

modified_clean.year =
    Int.(
        modified_clean.year
    )

# =====================================================================
# 6. Join baseline and marginal runs
# =====================================================================

diagnostic =
    innerjoin(
        base_clean,
        modified_clean,
        on = [
            :trialnum,
            :year
        ]
    )

diagnostic.delta_ch4_ppb =
    diagnostic.ch4_modified_ppb .-
    diagnostic.ch4_base_ppb

# Keep the policy-analysis horizon.
diagnostic = filter(
    row ->
        2020 <= row.year <= IMPACT_HORIZON,
    diagnostic
)

# Add explicit trial IDs for transparency.
diagnostic =
    leftjoin(
        diagnostic,
        trial_design,
        on = :trialnum
    )

sort!(
    diagnostic,
    [
        :trialnum,
        :year
    ]
)

# =====================================================================
# 7. Measure cross-trial variation in the marginal CH4 impulse
# =====================================================================

diagnostic_summary = combine(
    groupby(
        diagnostic,
        :year
    ),

    :delta_ch4_ppb =>
        minimum =>
        :min_delta_ch4_ppb,

    :delta_ch4_ppb =>
        maximum =>
        :max_delta_ch4_ppb,

    :delta_ch4_ppb =>
        mean =>
        :mean_delta_ch4_ppb,

    :delta_ch4_ppb =>
        std =>
        :sd_delta_ch4_ppb
)

diagnostic_summary.range_delta_ch4_ppb =
    diagnostic_summary.max_delta_ch4_ppb .-
    diagnostic_summary.min_delta_ch4_ppb

sort!(
    diagnostic_summary,
    :year
)

max_cross_trial_range =
    maximum(
        abs.(
            diagnostic_summary.range_delta_ch4_ppb
        )
    )

# =====================================================================
# 8. Additional trial-level QA
# =====================================================================

trial_summary = combine(
    groupby(
        diagnostic,
        :trialnum
    ),

    :delta_ch4_ppb =>
        maximum =>
        :peak_delta_ch4_ppb,

    :delta_ch4_ppb =>
        sum =>
        :sum_delta_ch4_ppb
)

trial_summary =
    leftjoin(
        trial_summary,
        trial_design,
        on = :trialnum
    )

println("Trial-level CH4 impulse response")
println("--------------------------------")

for row in eachrow(
    trial_summary
)

    println(
        "Trial ",
        row.trialnum,
        " | RFF ",
        row.rffsp_id,
        " | FaIR ",
        row.fair_parameter_set_id,
        " | peak ΔCH4 = ",
        row.peak_delta_ch4_ppb,
        " ppb"
    )
end

println()

println(
    "Maximum cross-trial range in ΔCH4: ",
    max_cross_trial_range,
    " ppb"
)

println()

# =====================================================================
# Interpretation
# =====================================================================

const CH4_INVARIANCE_TOLERANCE = 1e-10

if max_cross_trial_range <
   CH4_INVARIANCE_TOLERANCE

    println(
        "PASS: marginal atmospheric CH4 response is effectively " *
        "identical across these GIVE trials."
    )

    println(
        "For the ozone module we therefore do NOT need a separate " *
        "trial-specific atmospheric CH4 impulse response."
    )

    println(
        "Ozone Monte Carlo variation can inherit the RFF " *
        "socioeconomic/VSL trajectories and GIVE discounting while " *
        "using the common GIVE/FaIR CH4 impulse response."
    )

else

    println(
        "RESULT: marginal atmospheric CH4 response varies across GIVE trials."
    )

    println(
        "The ozone Monte Carlo module must therefore carry the " *
        "trial-specific CH4 impulse response as well as the " *
        "socioeconomic/VSL trajectories."
    )
end

# =====================================================================
# 9. Save
# =====================================================================

save(
    CH4_DIAGNOSTIC_PATH,
    diagnostic
)

save(
    CH4_DIAGNOSTIC_SUMMARY_PATH,
    diagnostic_summary
)

println()
println("Saved:")
println(
    "  ",
    CH4_DIAGNOSTIC_PATH
)
println(
    "  ",
    CH4_DIAGNOSTIC_SUMMARY_PATH
)

println()
println("NEXT STEP")
println("=========")

println(
    "Use mc_trial_design.csv as the single source of truth for " *
    "RFF and FaIR trial IDs in both the GIVE monetary library " *
    "and the ozone monetary library."
)

println(
    "The existing 5-trial proof-of-concept results will then be " *
    "rerun with these explicit IDs so that alignment is reproducible " *
    "without relying on random-seed behaviour."
)