# Methane–ozone mortality extension

The standard GIVE damage functions omit the respiratory mortality damages associated with methane's contribution to tropospheric ozone. This extension adapts the reduced-form McDuffie et al. (2023) approach to GIVE-consistent scenarios, populations, valuation and discounting.

## Core method

A deterministic difference in methane concentrations between baseline and policy FaIR trajectories rescales stored country-year respiratory mortality responses from the published reference experiment. This atmospheric response is coupled with GIVE trial-specific population, all-cause mortality and value-of-statistical-life trajectories.

The reference pulse is **275 Mt CH₄ in 2020**, originally mapped to a 100 ppb methane concentration perturbation. The implementation uses that reference for scaling, not as a replacement for the policy-specific FaIR concentration trajectory.

## Coverage

- Respiratory ozone mortality is included.
- Avoided premature deaths and monetised benefits can both be reported.
- Ozone response is represented through 2100, whereas climate damages may extend to 2300.
- Ozone chemistry and epidemiological response-table uncertainty are not fully sampled in the current production implementation.
- Cardiovascular ozone mortality, morbidity and ozone-related crop effects remain outside this component.

Scientific source: [McDuffie et al. (2023)](https://doi.org/10.1029/2023EF003853). See [validation](validation.md) and [implementation methods](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/METHODOLOGY.md).
