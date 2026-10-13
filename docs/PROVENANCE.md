# Run traceability

The Julia package keeps the upstream MimiGIVE name, UUID and licence. Scientific attribution is in README, the labour MIT notice and `provenance/labour_provenance.json`. Historical private project evidence is outside this public repository.

Public runners copy configuration, explicit aligned design and scenario inputs to their output evidence. They record Julia version and SHA-256 of code, Project/Manifest, core GIVE inputs and the minimum external labour/MOMM files. These are run-start records, not completion certificates; inspect the stage's validation output and preserve partial failures separately.

The combine wrapper rejects shared input/code hash differences or changes since the climate/ozone stages ran. Choose a fresh output directory and keep code/configuration/input files fixed between stages.

For a scientific result release, retain the exact code commit, Julia version, dependency manifest, original inputs/licences, explicit trial identities, random seed, validation and output tables. RFF per-trajectory provenance still requires a separately supplied dataset/version manifest. Binary artifact and cross-platform compatibility must be checked for the target machine.

New trial generation uses independent Julia MersenneTwister streams. A seed alone is not sufficient to reconstruct a design from another RNG implementation/version: preserve the CSVs. Synthetic fixture identities are illustrative, not a calibrated study design.
