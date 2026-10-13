# Outputs and interpretation

Stages write `output_dir/policy_scenarios`, `policy_ozone`, `policy_combined`, each with `production` or `data_smoke`. Existing outputs are refused. Stage metadata/QA and scenario copies are retained. Wrapper adds `provenance/<stage>_<mode>` with configuration/design copies, Julia version and input/code/environment hashes. These are run-start records, not completion certificates. Failed runs can leave partial evidence; retry in a new directory.

Climate exports annual/trial damage-channel and physical mortality tables, global PV, regional labour, and `give_discount_factors_trials.csv`/metadata. Ozone exports deterministic atmospheric evidence, trial annual respiratory mortality/money, physical totals and PV. Combination validates keys, scenario/response/trial coverage, physical equality and accounting, then writes:

- `global_total_societal_pv_trials.csv` plus response summaries/central means.
- Global channel PV summaries.
- Physical mortality by globe/EU27/DEU, including temperature/ozone.
- `final_central_results.csv`, `validation.json`.

Inspect actual column units/metadata. `usd2005` denotes dollars at2005 price levels; counts are undiscounted deaths. Full PV combines climate2300 and ozone2100. Regional mortality is not full regional economic benefit. Quantiles must be calculated from aligned sums, not sums/means of quantiles.

Pulse exports: `annual_<ISO|Lancet>_<year>.csv`, `discounted_sector_trials.csv`, `central_labor_mean.csv`, `temperature_mortality_annual_trials.csv`, `temperature_mortality_cumulative_trials.csv`, plus per-pulse evidence. Climate factors are USD2005/tonne gas; normalization is1MtCH4, converted consistently to tonnes. These are climate/labour factors, not ozone-inclusive full-policy benefit; test linearity before applying to large persistent interventions.

Historical ex_* scripts depended on caches/fixed100-trial runs and are excluded. CO2 SCC remains available in the core API, but portable pulse wrapper is CH4-only. EUR2026 conversion, costs and benefit-cost ratios belong to separate ECF reporting.

The wrapper refuses combination if prior climate/ozone input/code hashes disagree or shared files have changed since the stages ran. It does not remove partial runs.
