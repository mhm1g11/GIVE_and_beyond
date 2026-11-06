# Ramsey discounting and monetary valuation

GIVE discounts future welfare effects through consumption paths. The current policy implementation applies the Ramsey form below, rather than using a single constant discount rate for all future years.

```{math}
DF_t = \left(\frac{C_0}{C_t}\right)^\eta \frac{1}{(1+\rho)^{t-t_0}}
```

Here `C_t` is consumption at time `t`, `C_0` consumption in the valuation year, `η` the elasticity of marginal utility of consumption and `ρ` the pure rate of time preference.

The published scientific implementation note records **η = 1.244458999** and **ρ = exp(0.001972641) − 1**, or approximately 0.1975% annually, for its documented policy configuration. These should not be confused with other MimiGIVE defaults or alternate project specifications.

The code expresses native monetary outputs in **2005 US dollars**. Conversion to a common price year or euros for a policy comparison is a separate, explicitly documented post-processing step. Ozone-related mortality is monetised with GIVE-consistent country and year VSL values; response-specific consumption produces separate ISO/Lancet discount factors.

See [methodology and formula source](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/METHODOLOGY.md), together with [input schema](https://github.com/mhm1g11/GIVE_and_beyond/blob/release-candidate/docs/INPUTS.md).
