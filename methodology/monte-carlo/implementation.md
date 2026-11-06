# Monte Carlo implementation and computational lessons

## Computational design

The climate stage pairs baseline and policy models for each aligned draw and couples sea-level damages using CIAM offline. The ozone stage uses a deterministic policy concentration response and socioeconomic trial variation. Results are combined using explicit trial identities and response-specific discount factors.

## Known practical constraints

The documented two-trial run is a **smoke test**, not an uncertainty estimate. Production ensembles may take hours and create several GiB of data. The climate pathway has long annual horizons and can be computationally expensive even for a few draws. Ozone arrays may be memory intensive.

## Safeguards and workarounds

- Validate input schemas, paths, units and trial-design uniqueness before execution.
- Use fresh output directories; policy wrappers refuse existing stage outputs.
- Persist the aligned trial-design file so its random identities are not silently regenerated.
- Perform cheap table-only validations before full GIVE/CIAM model execution.
- Keep baseline and policy climate identities aligned and verify sign conventions.
- Avoid running any costly model during website generation. Publish validated static figures and summaries instead.

See [resource estimates and recommended checks](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/VALIDATION.md) and [release report](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/RELEASE_REPORT.md).
