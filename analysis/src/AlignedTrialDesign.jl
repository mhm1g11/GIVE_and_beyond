module AlignedTrialDesign
using Random, StatsBase, FileIO, CSVFiles, DataFrames
export load_or_create_trial_design

"""
Reuse a valid existing design byte-for-byte. A changed trial count requires an
explicit allow_replace=true or allow_extend=true for growth only. Extension
preserves all existing rows and appends the suffix of the seeded new design.
New designs use independent RFF/FaIR RNGs with
seed and seed+1; remaining GIVE draws use seed in the calling scripts.
"""
function load_or_create_trial_design(path; n_trials::Int=100,
                                     seed::Int=20260908, allow_replace::Bool=false,
                                     allow_extend::Bool=false)
    n_trials > 0 || throw(ArgumentError("n_trials must be positive"))
    existing = nothing
    if isfile(path)
        existing = DataFrame(load(path))
        required = [:trialnum, :rffsp_id, :fair_parameter_set_id]
        all(x -> x in propertynames(existing), required) || error("Invalid trial design schema")
        existing.trialnum == collect(1:nrow(existing)) || error("Trial IDs must be consecutive 1:N")
        all(x -> 1 <= x <= 10000, existing.rffsp_id) || error("Invalid RFF IDs")
        all(x -> 1 <= x <= 2237, existing.fair_parameter_set_id) || error("Invalid FaIR IDs")
        if nrow(existing) == n_trials
            return existing # Never rewrite/regenerate a matching production design.
        end
        (allow_replace || (allow_extend && n_trials > nrow(existing))) || error("Refusing to replace $(nrow(existing))-trial design with $n_trials trials. " *
                               "Use GIVE_EXTEND_TRIAL_DESIGN=true for a prefix-preserving extension, or GIVE_REPLACE_TRIAL_DESIGN=true for replacement.")
    end
    design = DataFrame(
        trialnum=collect(1:n_trials),
        rffsp_id=sample(MersenneTwister(seed), collect(1:10000), n_trials; replace=true),
        fair_parameter_set_id=sample(MersenneTwister(seed+1), collect(1:2237), n_trials; replace=true))
    if allow_extend && !isnothing(existing)
        n_trials > nrow(existing) || error("Extension cannot shrink an existing design")
        design = vcat(existing, design[nrow(existing)+1:end, :])
        isequal(design[1:nrow(existing), :], existing) || error("Extension changed existing draws")
    end
    save(path, design)
    return design
end
end
