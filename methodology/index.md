# GIVE Methane Methodology

A living methodology for developing methane-reduction scenarios and valuing their global societal impacts using an extended version of the Greenhouse Gas Impact Value Estimator (GIVE).

The framework combines methane emission pathways with GIVE's climate and economic damages, a methane–ozone respiratory-mortality extension, and an optional published labour-productivity component.

## How to read this book

1. **[Methane scenario development](methane-scenarios/index.md)** explains the construction and validation of methane-emissions counterfactuals.
2. **[GIVE](give/index.md)** documents the base model, damage-function coverage, consumption discounting and monetary valuation.
3. **[Ozone extension](ozone/index.md)** explains the additional health pathway and its validation.
4. **[Potential extensions](extensions/index.md)** is a research backlog, not part of current totals.
5. **[Monte Carlo framework](monte-carlo/index.md)** records uncertainty alignment, computational constraints and reproducibility safeguards.
6. **[Scenarios and results](scenarios/index.md)** is for verified runs with traceable configurations and data provenance.

## Implementation status

| Component | Status in the public GIVE fork |
| --- | --- |
| Original GIVE climate and damage pathways | Retained |
| Original GIVE agriculture damage function | **Retained and included** |
| Revised 2026 agriculture damage function | **Not implemented**; future candidate |
| Labour-productivity damage extension | Implemented as optional module; required by the documented policy wrapper |
| Methane–ozone respiratory mortality | Implemented |
| Full-pathway methane scenario comparison | Implemented through externally supplied annual pathways |
| Scenario-specific emissions baselines and policy results | To be documented and published only after validation and data-rights review |

This book describes the code as it exists. Planned methodology, published scientific estimates, synthetic examples and validated policy results must be labelled separately. External datasets and internal client material are **not** automatically available for public redistribution.

## Source and attribution

- [GIVE fork and implementation code](https://github.com/mhm1g11/GIVE_and_beyond/tree/release-candidate)
- [Scientific implementation note](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/METHODOLOGY.md)
- [Differences from upstream GIVE](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/UPSTREAM_CHANGES.md)
- [Data requirements and licensing](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/DATA.md)

Scientific foundation: [Rennert et al. (2022)](https://doi.org/10.1038/s41586-022-05224-9). Ozone extension: [McDuffie et al. (2023)](https://doi.org/10.1029/2023EF003853). Labour extension: [Moore et al. (2026)](https://doi.org/10.1038/s41558-026-02749-z).

*Publication note.* This website is a methodological work in progress and does not itself constitute a validated new policy estimate.
