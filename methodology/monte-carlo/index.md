# Monte Carlo framework

The full-pathway policy workflow uses explicit trial identifiers to align stochastic RFF socioeconomic pathways, FaIR climate draws, GIVE damage components and the labour response formulations. Baseline and policy are paired within the same trial.

## Scientific purpose

The distribution of avoided damages reflects uncertainty in model inputs and response parameters included in the design. It must not be interpreted as encompassing every structural, policy or atmospheric uncertainty.

ISO and Lancet are valued separately, then paired monetary values may be averaged within each aligned trial. Climate and ozone damages are combined **within trials before quantiles are calculated**. Averaging marginal quantiles would give an incorrect combined distribution.

## Reproducibility

The trial-design CSV, scenario input, model commit, external-data versions, conversion assumptions, reference tables and output checksums belong to every reported scenario. Keep synthetic smoke tests separate from scientific production estimates.

See [technical implementation and computational lessons](implementation.md), [data contract](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/INPUTS.md) and [validation](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/VALIDATION.md).
