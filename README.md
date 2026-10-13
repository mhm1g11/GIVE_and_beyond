# GIVE_and_beyond

A Julia fork of the **Greenhouse Gas Impact Value Estimator (GIVE)** for evaluating methane emissions interventions, including climate damages, methane-ozone respiratory mortality, monetary valuation and labour productivity. The Julia package remains **MimiGIVE**; `GIVE_and_beyond` is the repository name.

The policy workflow accepts new annual methane mitigation pathways and explicit aligned Monte Carlo designs. It retains GIVE's climate, agriculture, temperature mortality, energy and sea-level damage functions. The included example is **synthetic**: it demonstrates the input contract and is not a scientifically validated production scenario.

## Quick start: installation and input check

Install **Julia 1.10.12** and Git, then:

```sh
git clone --single-branch --branch release-candidate https://github.com/mhm1g11/GIVE_and_beyond.git
cd GIVE_and_beyond
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no scripts/validate_inputs.jl --config examples/run.toml
julia --startup-file=no test/runtests.jl
julia --project=. --startup-file=no test/components.jl
```

The preflight and tests do not run the full model. Instantiation downloads Julia packages and binary artifacts; allow network access and disk space. These commands also work in PowerShell. Julia 1.10 is declared compatible; 1.10.12 is the tested version. `Project.toml` lists dependencies and `Manifest.toml` pins their versions. Python is not required by the modelling workflow.

**A clone alone is not enough for a policy run.** Obtain the external datasets below, configure their paths, and validate them before starting calculations. Installation on a clean computer has not been exercised in this release preparation.

## Origin, developers and attribution

GIVE was developed by the Resources for the Future / UC Berkeley team and collaborators, including Kevin Rennert, Frank Errickson, Brian Prest, Lisa Rennels, Richard Newell, William Pizer, Cora Kingdon, Jordan Wingenroth, Roger Cooke, Bryan Parthum, David Smith, Kevin Cromar and David Anthoff. Credit all [upstream contributors](https://github.com/rffscghg/MimiGIVE.jl/graphs/contributors).

- Upstream: [rffscghg/MimiGIVE.jl](https://github.com/rffscghg/MimiGIVE.jl).
- GIVE science: Rennert et al. (2022), [Comprehensive evidence implies a higher social cost of CO2](https://doi.org/10.1038/s41586-022-05224-9).
- Ozone mortality: McDuffie et al. (2023), [The Social Cost of Ozone-Related Mortality Impacts From Methane Emissions](https://doi.org/10.1029/2023EF003853); [MOMM-RFT v1.0 data/code](https://doi.org/10.5281/zenodo.8276748).
- Labour: Moore et al. (2026), [publication](https://doi.org/10.1038/s41558-026-02749-z), [published implementation v1.0.1](https://github.com/lrennels/paper-2026-give-labor-ag/tree/v1.0.1).

This fork adds full-pathway methane policy orchestration, GIVE/FaIR-to-MOMM coupling, GIVE population/mortality/VSL valuation, opt-in published labour responses, aligned uncertainty calculations, regional mortality and labour aggregation, and exports. Labour equations are adapted from the published implementation. See [differences from upstream](docs/UPSTREAM_CHANGES.md).

Code retains the upstream MIT [LICENSE](LICENSE) and [labour MIT notice](provenance/labour_LICENSE). Cite the scientific sources when using their methods. Software licensing does not grant rights to third-party datasets; their terms and attribution remain applicable.

## External data: obtain separately

| Dataset | Default location in this checkout | Required for |
| --- | --- | --- |
| Published labour response tables, mappings and selected 2017 income CSV | `external/labour/` | Labour-enabled climate and ozone valuation |
| MOMM-RFT reference files | `external/MOMM-RFT/input/` | Ozone mortality; raw lookup tables also build annual denominators |
| Derived MOMM annual socioeconomic reference CSV | `external/momm_reference_socioeconomics.csv` | Ozone valuation; generated with the reference stage |
| RFF-SP v5 trajectories | Installed MimiRFFSPs/DataDeps `rffsps_v5` location | RFF-based model runs and new trial identities |

[DATA.md](docs/DATA.md) lists exact files, columns, units, source releases, licences and acquisition instructions. Labour/GTAP-derived data are excluded because redistribution rights need separate assessment. The selected income CSV may need extraction from the published Parquet; this repository does not supply a substitute or an automatic extractor. RFF trajectories may occupy several GiB. The wrappers disable automatic acceptance of DataDeps downloads; arrange these data deliberately before running.

`external/`, `outputs/` and `local/` are ignored by Git. Keep user inputs with sensitive or restricted contents in those locations or outside the checkout.

## Provide and run a NEW methane scenario

1. Prepare a CSV with exactly `year,avoided_ch4_mt`. Values are nonnegative **Mt CH4/year** (not CO2-equivalent). Supply every year from your valuation year through **2300**, including explicit zeroes after mitigation stops. Unique integer years are required. There is no automatic annual interpolation or post-2050 extrapolation.
2. Use `examples/run.toml` as a template. Configure one or more uniquely named `[[scenarios]]`, their CSV paths, external data roots, explicit trial-design files and a fresh `output_dir`. All relative paths resolve against the TOML file, so update them when moving the template.
3. Set `run.trials` to the exact design row count (at least two). Trial CSVs align RFF, FaIR and labour identities. [INPUTS.md](docs/INPUTS.md) documents their formats and `scripts/create_trial_design.jl` for generating a new design; existing files are never replaced.
4. Validate before running. The commands below use the synthetic template; replace its path with your configured TOML for your scenario.

```sh
julia --startup-file=no scripts/validate_inputs.jl --config examples/run.toml
```

If the annual MOMM denominator CSV is absent, derive it once from the separately obtained lookup tables. This processes tables without running GIVE:

```sh
julia --project=. --startup-file=no scripts/run_policy.jl --config examples/run.toml --stage reference
julia --startup-file=no scripts/validate_inputs.jl --config examples/run.toml --external
```

Once external inputs are ready, run the stages in order. **These commands perform model calculations**, including CIAM in the climate stage. `--data-smoke` uses the first two design rows and the supplied complete pathway; it is a small execution check, not a robust uncertainty analysis.

```sh
julia --project=. --startup-file=no scripts/run_policy.jl --config examples/run.toml --stage climate --data-smoke
julia --project=. --startup-file=no scripts/run_policy.jl --config examples/run.toml --stage ozone --data-smoke
julia --project=. --startup-file=no scripts/run_policy.jl --config examples/run.toml --stage combine --data-smoke
```

For a reviewed production analysis, replace `--data-smoke` with `--production` consistently in all three commands. Production uses all configured rows. Existing stage output directories are refused; use a new `output_dir` when retrying. Keep code and input files unchanged between stages: combination checks their recorded hashes.

For CH4 pulse-year **climate/labour** damage factors (additional SCC/CIAM calculations):

```sh
julia --project=. --startup-file=no scripts/run_pulses.jl --config examples/run.toml --years 2025,2030,2035,2040,2045,2050
```

This wrapper does not export ozone pulse factors. Core MimiGIVE CO2/SCC APIs also remain available. See [validation and resource costs](docs/VALIDATION.md).

## Outputs and interpretation

Stages write `policy_scenarios`, `policy_ozone` and `policy_combined` under the configured output directory, with separate `data_smoke` / `production` subdirectories. Combined exports include `global_total_societal_pv_trials.csv`, response summaries, `final_central_results.csv` and `validation.json`. Scenario copies, configuration/trial design and input/code hashes accompany the run.

Monetary outputs use **USD2005** unless explicitly labelled otherwise. Benefits are baseline minus policy damages; a channel may be negative. Physical avoided deaths are **undiscounted**. Global societal PV combines climate/labour damages through **2300** with ozone through **2100**. EU27/Germany mortality reports describe damage incidence, not complete regional economic benefit or automatically a separate intervention. [OUTPUTS.md](docs/OUTPUTS.md) explains units, accounting and pulse-factor interpretation.

## Scientific assumptions and uncertainty

The original FaIR, BRICK, socioeconomic and GIVE damage functions are retained; CIAM uses perfect foresight without a GDP damage cap in the policy workflow. Labour uses the published ISO and Lancet response tables separately, a fixed 2017 income baseline and a 0.82-degree temperature-baseline adjustment. Original GIVE agriculture remains; incomplete crop extensions are excluded.

Ozone policy atmosphere is **deterministic**: one GIVE/FaIR CH4 concentration difference per scenario is reused across trials to scale the McDuffie central multi-model/epidemiological response. Trial population, mortality, VSL and consumption discounting vary. The Monte Carlo distribution does not sample ozone atmospheric-model or epidemiological uncertainty.

Ramsey parameters are `PRTP=exp(0.001972641)-1` and `eta=1.244458999`. Approximately 2% near-term consumption discounting does **not** mean PRTP=2%. ISO/Lancet monetary valuations are calculated separately and the central result is their paired arithmetic mean. Combine aligned trial values before computing quantiles. These assumptions are fixed in the validated workflow; changing them requires explicit scientific review.

See [METHODOLOGY.md](docs/METHODOLOGY.md) for equations, coverage and limitations and [PROVENANCE.md](docs/PROVENANCE.md) for run traceability.

## Known issues and future extensions

External data acquisition and the selected labour income extraction require manual setup. Binary artifacts and complete installation on a new computer remain untested. A dependency emits a MCMCDiagnostics deprecation warning. Ozone trial arrays are held in memory; large ensembles can need considerable RAM/storage. Full-model runtime depends on trial/scenario count and CIAM; budget before launching production.

Scientific limitations include fixed ozone/NOx calibration, response transfer/linearity, incomplete health endpoints and adaptation, different horizons, crosswalk gaps, labour extrapolation beyond response knots and far-future socioeconomic uncertainty. Labour-enabled equity-weighted / legacy disaggregated SCC modes are unsupported. Future work includes bounded-memory processing, more geographic reporting, explicit atmospheric/health sensitivity experiments and a tested scientific-assumption configuration layer.

The implementation derives from a completed research workflow. Release checks validate syntax, inputs and isolated components; they do not imply that the synthetic example or a new user's inputs constitute a validated production study.

| Directory | Contents |
| --- | --- |
| `src/`, `data/` | MimiGIVE implementation and existing GIVE core model inputs |
| `analysis/` | Policy, ozone, climate/pulse and trial-design kernels |
| `scripts/`, `examples/` | Portable CLI, configuration and synthetic fixtures |
| `test/` | Fast safeguards and optional component/reference checks |
| `docs/`, `provenance/` | Methodology, use, validation and third-party attribution |

[Publication guidance](docs/PUBLICATION.md) explains the clean branch and safe default-branch change. Existing historical `main` is preserved; use a single-branch clone for a lightweight checkout.
