# Damage-function coverage

| Damage pathway | Treatment in this fork |
| --- | --- |
| Temperature-related mortality | Retained original GIVE component |
| Energy demand | Retained original GIVE component |
| Sea-level rise | Retained original GIVE/BRICK/CIAM coupling |
| Agriculture | **Original GIVE agriculture component retained** |
| Labour productivity | **Added**, based on the published 2026 implementation |
| Ozone respiratory mortality | **Added**, documented separately |
| Revised 2026 agriculture | **Not implemented** |
| Ozone cardiovascular mortality and morbidity | Not implemented |

## Labour productivity

The fork includes published labour-response functions from Moore et al. (2026), with separate ISO and Lancet formulations. It maps regional welfare impacts to GIVE's socioeconomic structure, including agricultural and non-agricultural labour exposure. The labour module is optional in the library and required by the documented policy workflow.

The central monetary estimate pairs ISO and Lancet at trial level. Both represent **labour productivity damages**, not updated crop-yield damages.

Implementation: [labour components](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/src/components/labor_damages.jl), [labour utilities](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/src/utils/labor.jl). Scientific evidence: [Moore et al. (2026)](https://doi.org/10.1038/s41558-026-02749-z).

## Agriculture

The original GIVE agriculture damage function is part of the climate valuation. A revised agriculture module appears in the published 2026 labour-and-agriculture work, but **has not been incorporated into this fork**. It remains a [future extension](../extensions/index.md) and must not be included a second time by applying standalone agriculture estimates.

Implementation details and validation notes: [scientific implementation](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/METHODOLOGY.md).
