# Public release contents and checks

The clean release retains the GIVE implementation, opt-in labour, methane-ozone mortality/valuation, aligned Monte Carlo policy orchestration and climate/labour pulse exports. Package identity remains MimiGIVE. README provides clone/install/preflight/run commands; supporting documentation covers data formats/acquisition/licensing, methodology, outputs, validation, limitations, upstream differences and run traceability.

Private audit/coal/provenance reconstruction artifacts, historical results, unbundled restricted labour/MOMM/RFF datasets and obsolete regression scaffolding are excluded. Appropriate GIVE/labour MIT notices and scientific citations remain. Model code was not substantially refactored during final publication polish.

Final publication checks: documentation links, example schema, Julia syntax, fast safeguards, isolated labour/ozone components, explicit trial-design guards and definition-only entry-point loading. No production, CIAM or Monte Carlo calculation, dependency installation or substantial download was performed.

Practical limitations: external input acquisition, manual selected labour income CSV extraction, several-GiB RFF dataset, untested clean-machine artifact installation and model resource needs. The synthetic fixture is not a validated production study. See DATA.md and VALIDATION.md.

Publication uses a new-root `release-candidate` branch. Existing `main` is preserved; default-branch change is a separate non-destructive repository setting. Follow PUBLICATION.md.

Publication verification: 107 assertions passed (15 schema/hash safeguards, 50 syntax files, 10 isolated component checks, 14 trial-design guards, 11 entry-point checks and 7 provenance checks). Synthetic input preflight and local documentation links pass. Staged-file scanning found no credential patterns or machine-specific absolute paths.
