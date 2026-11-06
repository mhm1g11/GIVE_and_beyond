# Methane scenario development

This section documents how changes in fossil-energy policy are translated into annual avoided methane emissions. It distinguishes **international supply-chain emissions** linked to imports from **domestic production and assets**.

The public model accepts scenario pathways with annual `avoided_ch4_mt` values. The upstream construction of country, fuel and technology counterfactuals is a separate exercise and must be documented with its own source data and verification before publishing estimates.

## Shared calculation logic

For each fuel and source class, record the reference activity, applicable methane-intensity or emission factor, a counterfactual assumption, and the resulting emissions difference. Aggregate without double counting, keeping the geographic boundary, units, vintage and annual time profile explicit.

Document for every technology or abatement intervention: baseline operations, capture/leak/vent/flaring mechanism, assumed effectiveness, implementation timing, relevant regulation, cost treatment and uncertainty.

- [International emissions](international.md) covers fossil fuel imports and supply-chain boundaries.
- [Domestic emissions](domestic.md) covers domestic oil, gas and coal assets.
- [Benchmarks](benchmarks.md) records external evidence and checks.

**Current status:** chapter framework established. Do not treat any numerical example as a result of this fork until an archived, validated input dataset and corresponding code version are linked.
