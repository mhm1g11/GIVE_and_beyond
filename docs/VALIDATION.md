# Lightweight validation and resource costs

## Fast checks

Run from the checkout root:

```sh
julia --startup-file=no test/runtests.jl
julia --startup-file=no test/provenance.jl
julia --startup-file=no scripts/validate_inputs.jl --config examples/run.toml
julia --project=. --startup-file=no test/components.jl
julia --project=. --startup-file=no test/optional/validate_trial_design_guard.jl
julia --project=. --startup-file=no test/load_entrypoints.jl
```

These cover input schema/alignment, negative/nonfinite values, missing/duplicate years, cross-stage hash safeguards, syntax, run-provenance recording, synthetic isolated labour/ozone components and definition-only entry-point loading. They do not construct full GIVE or CIAM models. Installed dependencies are needed for the `--project` checks; no package installation is performed by the tests themselves. A MCMCDiagnostics deprecation warning is known.

`docs/RELEASE_REPORT.md` records the publication checks. The synthetic fixture is not a validated production scenario. No production/Monte Carlo/CIAM calculation was run as part of publication.

## Optional scientific data checks

- Set `MIMIGIVE_MOMM_DATA`, then run `julia --project=. test/optional/validate_momm_2020.jl`: table-only 275-Mt/2020 reference benchmark, 210324.797541092 deaths; no GIVE run.
- Set `MIMIGIVE_LABOR_DATA`, provide published reference code and real tables, then run `julia --project=. test/optional/validate_labor_component.jl`: isolated published-equivalence checks; no full GIVE/CIAM.

PowerShell environment syntax: `$env:MIMIGIVE_MOMM_DATA='path'`. Other shells use their native syntax.

## Model execution and practical costs

Dependency installation can download many packages/artifacts. RFF-SP data occupy several GiB and are acquired separately. Check availability, licences and the external-data preflight before running.

A two-trial `--data-smoke` climate -> ozone -> combine calculation is the first execution check for new inputs. Climate runs paired 551-year models and offline CIAM; even two trials can take minutes or longer. Ozone runs socioeconomic trials and a deterministic atmospheric policy response. Production ensembles can take hours and generate several GiB; memory needs can be substantial because ozone arrays are held in memory. Measure a small run before increasing trial count. Pulse-year exports perform additional SCC/CIAM calculations.

Use fresh output directories. Public wrappers refuse existing stage outputs; the underlying upstream SCC API retains some legacy stream-overwrite behavior. Labour-enabled legacy disaggregated/equity-weighted SCC modes remain unsupported. The release has not been tested with a clean-machine dependency installation or a full model run during publication preparation.
