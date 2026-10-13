# Scientific implementation

## GIVE and full-pathway interventions

The retained package uses original FaIR v1.6.2 climate, RFF/SSP socioeconomics, BRICK sea-level response, Cromar temperature mortality, Moore agriculture and GCAM-region energy damages. CIAM sea-level damages are coupled offline. Original GIVE agriculture remains; incomplete2026 crops are excluded.

The climate policy stage pairs baseline/policy models for each aligned draw, replacing the marginal methane pulse with the entire annual negative avoided-emissions vector. Climate/socioeconomic identities and remaining random draws are shared within pairs, scenarios and labour formulations. Atmospheric/damage effects continue after mitigation stops; explicit inputs through2300 prevent hidden tail extensions. Global annual baseline-minus-policy damage differences are valued to2300.

CIAM uses perfect foresight with GDP cap disabled. The ISO sea-level stream is reused for Lancet only after checking climate/sea-level equality. Consumption discount factors remain response-specific because labour enters net consumption. Global climate total equals temperature mortality+agriculture+energy+labour+sea-level damages. `total_excluding_slr` is an intermediate subtotal, not another channel.

## Labour

`src/components/labor_damages.jl`, `LaborSectorShare.jl`, `LaborDamageAggregator.jl` and `src/utils/labor.jl` implement published labour-only responses within GIVE.

Temperature is shifted by0.82Â°C to the1995–2015 baseline. GTAP welfare impacts are divided by initial sector incomes and interpolated over1,1.5,…,4Â°C with an additional(0,0) origin. Linear extrapolation applies outside knots, including below zero. Agricultural/non-agricultural response fractions multiply corresponding shares of country GDP; costs sum across sectors. Component costs use billionUSD2005/year; aggregation converts toUSD2005/year.

Agriculture output share evolves as `share2017*(income_per_capita/income2017)^(-0.31)`. Historical baseline is the fixed RFF6546 2017 vector converted USD2011â†’USD2005, independent of dynamic trial identity. ISO/Lancet use distinct published heat/labour-response tables; neither is a replacement crop model. The15 labour model draws are independent of FaIR identities; ID1 is deterministic ensemble.

Labour is optional in the package and required in the policy wrapper. Unsupported labour-enabled equity-weighted SCC and legacy spatial SCC streaming paths retain explicit errors; the policy workflow exports its own country mortality/labour views.

## Methane–ozone mortality

The reference experiment is275MtCH4 in2020, divided by2.75Mt/ppb for an initial100ppb perturbation with11.8-year decay. Stored central BenMAP respiratory-mortality responses for atmospheric multi-model mean (`MMM`, `Inverse.PE`) are the production default.

Ozone policy computes ONE deterministic GIVE/FaIR CH4 concentration difference per scenario through2100. Its ratio to the original reference perturbation rescales stored annual country mortality. Exponential decay is the reference denominator, not a replacement for FaIR policy dynamics. Alternative stored atmosphere/epidemiological tables remain explicit sensitivity APIs, not stochastic production draws.

Trial mortality is additionally scaled by GIVE population and all-cause death-rate ratios relative to MOMM reference tables. GIVE population millions are reconciled with MOMM thousands; death-rate ratios reconcile the source's per1000 convention. The reference builder derives age-weighted all-cause mortality from mean lookup tables **without** respiratory attributable fraction and interpolates annual denominators2020–2100. Money uses GIVE country/year VSL inUSD2005 rather than original MOMM valuation.

Reduced methane produces negative modified-minus-baseline mortality; avoided-death/benefit exports reverse that sign. Annual monetary benefit is avoided deaths×trialVSL. ISO/Lancet baseline consumption produces separate discount factors.

## Discounting and uncertainty

`DF_t=(C_valuation/C_t)^eta/(1+PRTP)^(t-valuation_year)`, `PRTP=exp(0.001972641)-1`, `eta=1.244458999`. PRTPâ‰ˆ0.1975%/year; approximately2% near-term consumption discounting also reflects growth. MimiGIVE API defaults are a different specification.

Climate trials use explicit aligned RFF/FaIR IDs, labour model IDs and remaining GIVE uncertainty streams. Ozone atmosphere, response table and health coefficient are deterministic; ozone variation is socioeconomic mortality/population, VSL and discounting. Distributions do not encompass total ozone chemistry/epidemiological uncertainty.

ISO/Lancet remain separate. Central monetary trial values average paired valuations; climate+ozone are combined per aligned trial before summarising. Never average separate quantiles to obtain quantiles of a central sum. Physically identical mortality streams are checked before merging. Use an ensemble large enough for the intended uncertainty analysis; the two-trial fixture is only an execution check.

## Geography, horizons and limitations

GIVE has184 country socioeconomic/labour/mortality streams. MOMM has201 response locations and a broader crosswalk. Unmatched locations retain physical ozone effects with scaling=1; without validVSL they are excluded from monetary valuation. Read coverage counts/QA before describing monetary geography as complete.

Global societal PV combines climate through2300 with ozone through2100. EU27/DEU combined mortality measures where deaths are avoided, not full regional economic benefits. A DEU intervention is a separate policy. Julia money isUSD2005; currency conversion and policy costs are outside this model.

Limitations: reduced-form transfer to new paths, linearity, fixed chemical/NOx calibration, no sampled ozone atmosphere/health uncertainty, different horizons, socioeconomic extrapolation, omitted health endpoints/adaptation/nonmarket effects, labour extrapolation outside knots, and historical environment uncertainty. Schema-valid pathways outside calibration need scientific review. Future work should measure memory/runtime, process ozone trials in bounded batches, add explicit sensitivity experiments and expand regional reporting without changing archived assumptions silently.
