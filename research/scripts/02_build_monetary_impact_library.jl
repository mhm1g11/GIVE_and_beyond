using Mimi
using MimiGIVE
using FileIO
using CSVFiles
using DataFrames
using Statistics
using Random

include(
    joinpath(
        @__DIR__,
        "config.jl"
    )
)

# ================================================================
# Explicit aligned Monte Carlo trial design
# ================================================================

const MC_SEED = 20260908

const TRIAL_DESIGN_PATH = joinpath(
    INPUT_DIR,
    "mc_trial_design.csv"
)

trial_design =
    DataFrame(
        load(
            TRIAL_DESIGN_PATH
        )
    )

function as_int(x)

    if x isa Integer
        return Int(x)
    end

    return parse(
        Int,
        strip(string(x))
    )
end

trial_design.trialnum =
    as_int.(
        trial_design.trialnum
    )

trial_design.rffsp_id =
    as_int.(
        trial_design.rffsp_id
    )

trial_design.fair_parameter_set_id =
    as_int.(
        trial_design.fair_parameter_set_id
    )

sort!(
    trial_design,
    :trialnum
)

const N_TRIALS =
    nrow(
        trial_design
    )

const RFFSP_IDS =
    collect(
        trial_design.rffsp_id
    )

const FAIR_IDS =
    collect(
        trial_design.fair_parameter_set_id
    )

trial_design.trialnum ==
    collect(1:N_TRIALS) ||
    error(
        "mc_trial_design.csv must contain consecutive trial numbers 1:N."
    )

# ================================================================
# Output files
# ================================================================

const TRIAL_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "monetary_impact_library_trials.csv"
)

const SUMMARY_OUTPUT_PATH = joinpath(
    OUTPUT_DIR,
    "monetary_impact_library_summary.csv"
)

mkpath(
    OUTPUT_DIR
)

mkpath(
    GIVE_RUN_DIR
)

# ================================================================
# Helpers
# ================================================================

function official_global_scc(
    result,
    sector::Symbol
)

    key = (
        region = :globe,
        sector = sector,
        dr_label = DISCOUNT_LABEL,
        prtp = PRTP,
        eta = ETA,
        ew = nothing,
        ew_norm_region = nothing
    )

    raw_values =
        result[
            :scc
        ][
            key
        ].sccs

    return [
        ismissing(x) ?
            NaN :
            Float64(x)
        for x in raw_values
    ]
end


function read_country_matrix(
    disagg_dir::String,
    folder::String,
    iso3::String,
    trialnums,
    years
)

    path = joinpath(
        disagg_dir,
        folder,
        "$(iso3).csv"
    )

    isfile(path) ||
        error(
            "Missing country file: $path"
        )

    df =
        DataFrame(
            load(
                path
            )
        )

    sort!(
        df,
        [
            :trialnum,
            :time
        ]
    )

    @assert sort(
        unique(
            df.trialnum
        )
    ) == trialnums

    @assert sort(
        unique(
            df.time
        )
    ) == years

    @assert nrow(df) ==
        length(trialnums) *
        length(years)

    matrix =
        permutedims(
            reshape(
                df.md,
                length(years),
                length(trialnums)
            )
        )

    return matrix
end


function build_discount_factors(
    cpc,
    years,
    pulse_year
)

    pulse_idx =
        findfirst(
            ==(pulse_year),
            years
        )

    pulse_idx === nothing &&
        error(
            "Pulse year $pulse_year not found."
        )

    discount_factors =
        zeros(
            size(cpc)
        )

    for trial in axes(
        cpc,
        1
    )

        for i in eachindex(
            years
        )

            year =
                years[i]

            if pulse_year <= year <= IMPACT_HORIZON

                discount_factors[
                    trial,
                    i
                ] =
                    (
                        cpc[
                            trial,
                            pulse_idx
                        ] /
                        cpc[
                            trial,
                            i
                        ]
                    )^ETA *
                    1 /
                    (1 + PRTP)^(
                        year -
                        pulse_year
                    )
            end
        end
    end

    return discount_factors
end


function discount_to_scc(
    md_matrix,
    discount_factors
)

    @assert size(
        md_matrix
    ) == size(
        discount_factors
    )

    return vec(
        sum(
            md_matrix .*
            discount_factors,
            dims = 2
        )
    )
end


function add_trial_rows!(
    output::DataFrame,
    pulse_year::Int,
    geography::String,
    metric::String,
    values
)

    length(values) ==
        N_TRIALS ||
        error(
            "Expected $N_TRIALS trial values for " *
            "$pulse_year / $geography / $metric."
        )

    for trial in eachindex(
        values
    )

        push!(
            output,
            (
                pulse_year,
                trial,

                Int(
                    trial_design.rffsp_id[
                        trial
                    ]
                ),

                Int(
                    trial_design.fair_parameter_set_id[
                        trial
                    ]
                ),

                geography,
                metric,
                Float64(
                    values[
                        trial
                    ]
                ),
                "USD2005_per_t_CH4"
            )
        )
    end
end

# ================================================================
# Main output table
# ================================================================

all_trials = DataFrame(
    pulse_year = Int[],
    trialnum = Int[],
    rffsp_id = Int[],
    fair_parameter_set_id = Int[],
    geography = String[],
    metric = String[],
    value = Float64[],
    unit = String[]
)

reference_cpc =
    Ref{Any}(
        nothing
    )

# ================================================================
# Console header
# ================================================================

println(
    "BUILDING EXPLICITLY ALIGNED GIVE MONETARY IMPACT LIBRARY"
)

println(
    "========================================================"
)

println()

println(
    "Gas:            ",
    GAS
)

println(
    "Pulse years:    ",
    first(
        PULSE_YEARS
    ),
    " to ",
    last(
        PULSE_YEARS
    )
)

println(
    "Impact horizon: ",
    IMPACT_HORIZON
)

println(
    "Trials:         ",
    N_TRIALS
)

println(
    "Random seed:    ",
    MC_SEED
)

println()

println(
    "Explicit trial design"
)

println(
    "---------------------"
)

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

# ================================================================
# Run each methane pulse year
# ================================================================

for pulse_year in PULSE_YEARS

    println()
    println(
        "================================================"
    )

    println(
        "PULSE YEAR ",
        pulse_year
    )

    println(
        "================================================"
    )

    run_dir = joinpath(
        GIVE_RUN_DIR,
        "monetary_pulse_$(pulse_year)"
    )

    if isdir(
        run_dir
    )

        rm(
            run_dir;
            recursive = true,
            force = true
        )
    end

    # ------------------------------------------------------------
    # Resetting the seed keeps all remaining GIVE random draws
    # aligned across pulse years.
    #
    # RFF socioeconomic and FaIR IDs are no longer random:
    # they are explicitly fixed by mc_trial_design.csv.
    # ------------------------------------------------------------

    Random.seed!(
        MC_SEED
    )

    println(
        "Running GIVE with explicit RFF/FaIR trial IDs..."
    )

    result =
        MimiGIVE.compute_scc(
            year = pulse_year,
            last_year = IMPACT_HORIZON,
            gas = GAS,

            n = N_TRIALS,

            discount_rates =
                DISCOUNT_RATES,

            fair_parameter_set =
                :deterministic,

            fair_parameter_set_ids =
                FAIR_IDS,

            rffsp_sampling =
                :deterministic,

            rffsp_sampling_ids =
                RFFSP_IDS,

            compute_sectoral_values =
                true,

            compute_disaggregated_values =
                true,

            save_cpc =
                true,

            output_dir =
                run_dir
        )

    disagg_dir = joinpath(
        run_dir,
        "results",
        "disaggregated_values"
    )

    # ------------------------------------------------------------
    # Establish trial/year dimensions
    # ------------------------------------------------------------

    sample_path = joinpath(
        disagg_dir,
        "mds_country_mortality",
        "$(GERMANY).csv"
    )

    isfile(sample_path) ||
        error(
            "Expected disaggregated mortality file not found: " *
            sample_path
        )

    sample_df =
        DataFrame(
            load(
                sample_path
            )
        )

    sort!(
        sample_df,
        [
            :trialnum,
            :time
        ]
    )

    trialnums =
        sort(
            unique(
                Int.(
                    sample_df.trialnum
                )
            )
        )

    years =
        sort(
            unique(
                Int.(
                    sample_df.time
                )
            )
        )

    @assert length(
        trialnums
    ) == N_TRIALS

    @assert trialnums ==
        collect(
            1:N_TRIALS
        )

    # ------------------------------------------------------------
    # Global per-capita consumption paths
    # ------------------------------------------------------------

    cpc_key = (
        region = :globe,
        sector = :total
    )

    cpc =
        result[
            :cpc
        ][
            cpc_key
        ]

    @assert size(
        cpc,
        1
    ) == N_TRIALS

    @assert size(
        cpc,
        2
    ) == length(
        years
    )

    # ------------------------------------------------------------
    # QA: same sampled socioeconomic worlds across pulse years
    #
    # Since the RFF IDs are now explicit, this is an additional
    # numerical verification rather than our only alignment method.
    # ------------------------------------------------------------

    if reference_cpc[] === nothing

        reference_cpc[] =
            copy(
                cpc
            )

        println(
            "Stored ",
            pulse_year,
            " consumption paths as alignment reference."
        )

    else

        cpc_difference =
            maximum(
                abs.(
                    cpc .-
                    reference_cpc[]
                )
            )

        println(
            "Max difference in baseline consumption draws vs ",
            first(PULSE_YEARS),
            ": ",
            cpc_difference
        )

        if cpc_difference <
           1e-10

            println(
                "Trial alignment QA: PASS"
            )

        else

            error(
                "Trial alignment QA failed: baseline consumption " *
                "paths changed across pulse years."
            )
        end
    end

    # ------------------------------------------------------------
    # Discount factors
    # ------------------------------------------------------------

    discount_factors =
        build_discount_factors(
            cpc,
            years,
            pulse_year
        )

    # ============================================================
    # GLOBAL
    # ============================================================

    global_total =
        official_global_scc(
            result,
            :total
        )

    global_mortality =
        official_global_scc(
            result,
            :cromar_mortality
        )

    global_agriculture =
        official_global_scc(
            result,
            :agriculture
        )

    global_energy =
        official_global_scc(
            result,
            :energy
        )

    global_slr =
        official_global_scc(
            result,
            :slr
        )

    global_total_excl_agriculture =
        global_mortality .+
        global_energy .+
        global_slr

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "total_monetised",
        global_total
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "total_monetised_excl_agriculture",
        global_total_excl_agriculture
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "temperature_mortality_monetised",
        global_mortality
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "agriculture_monetised",
        global_agriculture
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "energy_monetised",
        global_energy
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "globe",
        "slr_monetised",
        global_slr
    )

    # ============================================================
    # Country-level sector folders
    # ============================================================

    sector_folders = Dict(
        :mortality =>
            "mds_country_mortality",

        :energy =>
            "mds_country_energy",

        :slr =>
            "mds_country_slr"
    )

    # ============================================================
    # GERMANY
    # ============================================================

    germany_mortality_md =
        read_country_matrix(
            disagg_dir,
            sector_folders[
                :mortality
            ],
            GERMANY,
            trialnums,
            years
        )

    germany_energy_md =
        read_country_matrix(
            disagg_dir,
            sector_folders[
                :energy
            ],
            GERMANY,
            trialnums,
            years
        )

    germany_slr_md =
        read_country_matrix(
            disagg_dir,
            sector_folders[
                :slr
            ],
            GERMANY,
            trialnums,
            years
        )

    germany_mortality =
        discount_to_scc(
            germany_mortality_md,
            discount_factors
        )

    germany_energy =
        discount_to_scc(
            germany_energy_md,
            discount_factors
        )

    germany_slr =
        discount_to_scc(
            germany_slr_md,
            discount_factors
        )

    germany_total =
        germany_mortality .+
        germany_energy .+
        germany_slr

    add_trial_rows!(
        all_trials,
        pulse_year,
        GERMANY,
        "temperature_mortality_monetised",
        germany_mortality
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        GERMANY,
        "energy_monetised",
        germany_energy
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        GERMANY,
        "slr_monetised",
        germany_slr
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        GERMANY,
        "total_monetised_excl_agriculture",
        germany_total
    )

    # ============================================================
    # EU27
    # ============================================================

    eu_mortality_md =
        zeros(
            N_TRIALS,
            length(
                years
            )
        )

    eu_energy_md =
        zeros(
            N_TRIALS,
            length(
                years
            )
        )

    eu_slr_md =
        zeros(
            N_TRIALS,
            length(
                years
            )
        )

    for iso3 in EU27

        eu_mortality_md .+=
            read_country_matrix(
                disagg_dir,
                sector_folders[
                    :mortality
                ],
                iso3,
                trialnums,
                years
            )

        eu_energy_md .+=
            read_country_matrix(
                disagg_dir,
                sector_folders[
                    :energy
                ],
                iso3,
                trialnums,
                years
            )

        eu_slr_md .+=
            read_country_matrix(
                disagg_dir,
                sector_folders[
                    :slr
                ],
                iso3,
                trialnums,
                years
            )
    end

    eu_mortality =
        discount_to_scc(
            eu_mortality_md,
            discount_factors
        )

    eu_energy =
        discount_to_scc(
            eu_energy_md,
            discount_factors
        )

    eu_slr =
        discount_to_scc(
            eu_slr_md,
            discount_factors
        )

    eu_total =
        eu_mortality .+
        eu_energy .+
        eu_slr

    add_trial_rows!(
        all_trials,
        pulse_year,
        "EU27",
        "temperature_mortality_monetised",
        eu_mortality
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "EU27",
        "energy_monetised",
        eu_energy
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "EU27",
        "slr_monetised",
        eu_slr
    )

    add_trial_rows!(
        all_trials,
        pulse_year,
        "EU27",
        "total_monetised_excl_agriculture",
        eu_total
    )

    # ============================================================
    # Pulse-year console summary
    # ============================================================

    println()

    println(
        "Test means for ",
        pulse_year,
        ":"
    )

    println(
        "  Global total: ",
        mean(
            global_total
        ),
        " USD2005/t CH4"
    )

    println(
        "  Global total excl. agriculture: ",
        mean(
            global_total_excl_agriculture
        ),
        " USD2005/t CH4"
    )

    println(
        "  EU27 total excl. agriculture: ",
        mean(
            eu_total
        ),
        " USD2005/t CH4"
    )

    println(
        "  Germany total excl. agriculture: ",
        mean(
            germany_total
        ),
        " USD2005/t CH4"
    )

    GC.gc()
end

# ================================================================
# Sort trial-level library
# ================================================================

sort!(
    all_trials,
    [
        :pulse_year,
        :geography,
        :metric,
        :trialnum
    ]
)

# ================================================================
# Final alignment QA
#
# Every trial number must always map to the same explicit RFF/FaIR IDs
# across all pulse years, geographies and metrics.
# ================================================================

println()
println(
    "EXPLICIT TRIAL-DESIGN QA"
)

println(
    "========================"
)

for trialnum in 1:N_TRIALS

    rows = filter(
        row ->
            row.trialnum ==
            trialnum,
        all_trials
    )

    rff_ids =
        unique(
            rows.rffsp_id
        )

    fair_ids =
        unique(
            rows.fair_parameter_set_id
        )

    length(
        rff_ids
    ) == 1 ||
        error(
            "Trial $trialnum has multiple RFF IDs."
        )

    length(
        fair_ids
    ) == 1 ||
        error(
            "Trial $trialnum has multiple FaIR IDs."
        )

    rff_ids[1] ==
        trial_design.rffsp_id[
            trialnum
        ] ||
        error(
            "Trial $trialnum RFF ID does not match mc_trial_design.csv."
        )

    fair_ids[1] ==
        trial_design.fair_parameter_set_id[
            trialnum
        ] ||
        error(
            "Trial $trialnum FaIR ID does not match mc_trial_design.csv."
        )

    println(
        "Trial ",
        trialnum,
        ": RFF ",
        rff_ids[1],
        " | FaIR ",
        fair_ids[1],
        " | PASS"
    )
end

# ================================================================
# Summary
# ================================================================

summary = combine(
    groupby(
        all_trials,
        [
            :pulse_year,
            :geography,
            :metric,
            :unit
        ]
    ),

    :value =>
        mean =>
        :mean_value,

    :value =>
        median =>
        :median_value,

    nrow =>
        :n_trials
)

sort!(
    summary,
    [
        :pulse_year,
        :geography,
        :metric
    ]
)

# ================================================================
# Save
# ================================================================

save(
    TRIAL_OUTPUT_PATH,
    all_trials
)

save(
    SUMMARY_OUTPUT_PATH,
    summary
)

println()
println(
    "MONETARY IMPACT LIBRARY COMPLETE"
)

println(
    "================================"
)

println()

println(
    "Trial rows:   ",
    nrow(
        all_trials
    )
)

println(
    "Summary rows: ",
    nrow(
        summary
    )
)

println()

println(
    "Saved:"
)

println(
    "  ",
    TRIAL_OUTPUT_PATH
)

println(
    "  ",
    SUMMARY_OUTPUT_PATH
)

println()
println(
    "IMPORTANT"
)

println(
    "========="
)

println(
    "The RFF socioeconomic and FaIR parameter-set IDs are now " *
    "explicitly fixed by mc_trial_design.csv."
)

println(
    "All remaining stochastic GIVE parameters are kept aligned across " *
    "pulse years by resetting the same Monte Carlo seed before each run."
)

println(
    "Trial numbers can therefore be combined directly with the " *
    "trial-aligned ozone monetary library."
)

println(
    "These are still only ",
    N_TRIALS,
    " test trials and should not be interpreted as final uncertainty estimates."
)