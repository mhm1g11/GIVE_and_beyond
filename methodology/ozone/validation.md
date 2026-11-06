# Ozone validation and limits

## Published reference check

The published validation documentation gives an optional table-only check of the 275 Mt CH₄ 2020 pulse, with benchmark output **210,324.797541092** reference deaths, conditional on obtaining the specified MOMM-RFT external source tables. This is a validation target, not the result for an actual EU methane policy scenario.

See [validation commands and caveats](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/VALIDATION.md). The source data are acquired separately and are not part of the public fork.

## Integration checks

A scientific run should confirm the source/target methane-concentration scaling, temporal bounds, geographic crosswalk, reference population and baseline mortality denominators, units, signs of avoided deaths and valuation, and combined trial alignment.

## Uncertainty

The current code varies socioeconomic population/mortality, VSL and discount factors across trials. It holds the ozone atmospheric and epidemiological response tables fixed in the central implementation. Consequently, its monetary distribution is **not** a complete ozone-specific scientific uncertainty distribution.
