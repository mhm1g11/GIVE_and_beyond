# Standard GIVE and our application

The Greenhouse Gas Impact Value Estimator (GIVE) is a probabilistic integrated assessment framework for the social cost of greenhouse gases. This fork retains the original model architecture and adds pathways that value full annual methane interventions instead of only a marginal pulse.

## Analysis chain

Methane policy pathway → paired baseline and policy climate simulations (FaIR) → damage functions → consumption-based valuation and discounting → global present-value avoided damages.

Paired simulations share aligned socioeconomic and climate draws, reducing the risk that unrelated randomness is mistaken for a policy effect. The model retains the original FaIR climate response, BRICK sea-level response and offline CIAM damages.

## What is included?

See [damage-function coverage](damages.md) for the original agriculture module, the added labour component and the excluded 2026 agriculture revision. [Discounting and monetisation](discounting.md) covers Ramsey assumptions and monetary units.

The numerical details and current technical implementation are documented in [docs/METHODOLOGY.md](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/METHODOLOGY.md) and [docs/UPSTREAM_CHANGES.md](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/UPSTREAM_CHANGES.md).

Core GIVE science: [Rennert et al. (2022)](https://doi.org/10.1038/s41586-022-05224-9).
