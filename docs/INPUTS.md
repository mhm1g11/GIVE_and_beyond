# Portable input contract

`schema_version=1`. Relative paths resolve against the TOML file; absolute external-input paths are permitted but should not be shared as portable bundles.

| Setting | Meaning |
| --- | --- |
| `run.trials` | Exact row count, integer>=2 |
| `run.valuation_year` | First applied/discounted year, 2020–2100; default2025 |
| `run.seed` | Remaining GIVE stochastic draws; default20260908 |
| `run.output_dir` | Fresh output tree |
| `inputs.trial_design` | `trialnum,rffsp_id,fair_parameter_set_id` |
| `inputs.labor_design` | Above plus `labor_model_id,labor_model` |
| `inputs.labor_root` | External labour root; mapped to `MIMIGIVE_LABOR_DATA` |
| `inputs.momm_root` | External MOMM root |
| `inputs.momm_socio` | Annual denominator CSV; reference stage can generate it |
| `scenarios[].name` | Unique `[A-Za-z][A-Za-z0-9_-]*` |
| `scenarios[].path` | Annual mitigation CSV |

Dependency-free preflight CSVs use unquoted numeric/identifier cells, exact column order and no blank records. Paths belong in TOML. Synthetic fixtures are artificial, not calibrated evidence. Their two illustrative trial IDs have no claim to scientific representativeness.

Scenario: `year,avoided_ch4_mt`, Mt CH4/year (1Mt=1e6 metric tonnes; not CO2-equivalent). Finite nonnegative mitigation, unique integer years1750:2300; every year from valuation year through2300. Positive avoided methane becomes a negative emissions perturbation. No annual interpolation or hidden tail extension. Pre-valuation records are copied but not applied.

Designs: ordered `trialnum=1:N`; RFF IDs1:10000, FaIR IDs1:2237. Labour rows must match all three identities. Labour IDs2:16 select the15 individual response models; ID1 is deterministic ensemble, not MC. Labels must match `dimension_gcm.csv`. Both ISO and Lancet are required.

For NEW designs, configure absent CSV paths and desired count/seed, after dependency installation:

```sh
julia --project=. --startup-file=no scripts/create_trial_design.jl --config path/to/run.toml
```

Either existing file causes refusal. RFF/FaIR use independent MersenneTwister seed/seed+1 with replacement, preserving `AlignedTrialDesign`. New labour draws use Julia MersenneTwister(seed+2). Designs generated with another RNG/version need not match: preserve the actual CSVs for numerical comparison.

The wrapper preserves fixed Ramsey parameters,2300/2100 endpoints, ISO/Lancet pair, GIVE default VSL and MOMM central calibration. Changing scientific assumptions requires a reviewed extension. Standard regional views remain globe/EU27/DEU regardless of scenario names.

`--data-smoke` uses the first two rows and the supplied complete pathway. Hardcoded historical smoke scenarios are removed. For zero-policy testing supply an explicit all-zero CSV. `--production` uses every configured row.

Direct API users set `ENV["MIMIGIVE_LABOR_DATA"]` before `MimiGIVE.get_model(include_labor=true,labor_response=:ISO)`; the path is evaluated at call time. `get_model()` leaves labour off by default. Explicit `labor_ypc2017` can supply a USD2005 vector in GIVE country order, but changing the published fixed baseline must be documented.
