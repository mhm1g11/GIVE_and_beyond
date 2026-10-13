# Differences from upstream GIVE

The fork retains MimiGIVE's name, UUID and package version, original MIT notice, FaIR/BRICK/CIAM/SSP/RFF dependencies, agriculture, temperature mortality, energy, optional alternative damages, SCC and Monte Carlo APIs.

Additions are opt-in published labour components and aggregation, explicit labour MC identities, labour-aware global SCC streams, methane-ozone scaling/valuation, full-pathway paired policy stages, aligned climate/ozone combination, regional mortality/labour exports and pulse-year climate factors. Labour code derives from Moore et al. reference v1.0.1; its MIT notice is retained.

Portable wrappers add TOML paths, user-named scenarios and explicit trial count/seed, runtime labour data resolution via `MIMIGIVE_LABOR_DATA`, output overwrite guards and scientific input/code hashes. Reference-table generation does not run GIVE merely for a diagnostic. Smoke runs use explicit supplied CSVs. New labour designs use a documented Julia RNG; retain design CSVs when comparing runs.

Validated damage equations, response calibration, unit conversions, Ramsey parameters, climate2300/ozone2100 endpoints and ISO/Lancet treatment are retained. Original GIVE agriculture is preserved; incomplete crop extensions are excluded.

Historical caches, generated results, development runners, private policy builders, full depots and regression scaffolding without fixtures are excluded. Core CO2/SCC APIs remain. The upstream DataExplainer and ComponentDetails notebooks are retained as reference documentation; this README gives the current installation/workflow instructions.
