# Data acquisition and redistribution

`external/` is Git-ignored. Software MIT licensing does not settle rights to source datasets. No external datasets are downloaded by the fast tests.

| Input | Content and units | Handling |
| --- | --- | --- |
| GIVE core `data/` | Country/region mappings, FaIR forcing/parameter draws, BRICK posterior, CIAM inputs, mortality/energy coefficients, SSP tables | Existing upstream GIVE inputs; consult DataExplainer/ComponentDetails notebooks and applicable source terms |
| RFF-SP v5 | Socioeconomic trajectories, emissions/mortality, mapping tables | Obtain separately; severalGiB, dataset-specific terms |
| Labour tables | GTAP welfare response, income baseline, output shares, country/GCM mappings | External pending GTAP-derived data redistribution clarification |
| MOMM raw tables | BenMAP deaths, ISO/location crosswalk, mean population and age mortality | Obtain MOMM-RFT v1.0; its source declares data/figures CC BY 4.0 and code MIT; retain attribution and source conditions |
| Annual MOMM denominators | Derived population thousands and all-cause mortality rate, location/year/ISO keys | Generate reference stage; underlying licences still apply |
| Mitigation | User annual MtCH4/year | Synthetic example contains no ECF policy data |

## Labour input root

Obtain [published reference v1.0.1](https://github.com/lrennels/paper-2026-give-labor-ag/tree/v1.0.1), commit `5d034e751f1170c7c2fcaff2d0fcd96a8fdc54c8`. Arrange:

```text
202505_SectorShare_v2.csv
dimension_gcm.csv
region_crosswalk.csv
gtap_output/20260428_Plants_People_results_v4_ISO_Revision.csv
gtap_output/20260428_Plants_People_results_v4_Lancet_Revision.csv
ypc2017/rffsp_ypc2017_selected.csv
```

`provenance/labour_provenance.json` records original paths/hashes/transforms. Do not assume upstream filenames/schema remain identical. Loader requires `GCM`; crosswalk `iso3,gtap`; shares `gtap,agriculture`; baseline `trial,iso3,ypc2017_usd2011`; response `Country,Degrees,GCM,Scenario,ST_AG_Welfare_in_M_USD,ST_NONAG_Welfare_in_M_USD,Initial_Income_in_M_USD`. Selects `Scenario == "Labor Only (All Sectors)"`; complete country x model x warming keys required. Model order follows `examples/labour_model_names.csv`.

The selected 2017 CSV is a derived extraction. If unavailable, extract RFF6546 from the published income baseline in the indicated units/country order, or supply `labor_ypc2017` via package API. The candidate does not automate Parquet extraction or bundle a substitute. This remains a policy-wrapper setup blocker until the CSV is obtained. The full Parquet is unnecessary at runtime if the selected CSV is available; never invent baseline values for historical replication.

Published-equivalence tests additionally require `reference/src/utils.jl`, `reference/src/components/labor.jl`, and `reference/src/components/AgricultureShare.jl` under that root. Their MIT notice is retained locally; they are not production inputs.

## MOMM minimum layout

```text
input/BenMAP/Country Results Interpolated 2020-2100 by Model.csv
input/Final Country Grid Col_Row Index.csv
input/RFF/lookup_tables/rff_mort_means.csv
input/RFF/lookup_tables/rff_pop_means.csv
```

Obtain [MOMM-RFT v1.0](https://doi.org/10.5281/zenodo.8276748), cited in the [paper data-availability statement](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2023EF003853). Place this layout under `external/MOMM-RFT/` or configure another root. First two are production inputs; latter two generate denominators. BenMAP requires `Model,column,ModelYear,Inverse.PE`; sensitivity columns `Inverse.2_5,Inverse.97_5`. Crosswalk requires `COL,COUNTRY,RFF_iso_code,Region,SuperRegion`. Use the version associated with [McDuffie et al.](https://doi.org/10.1029/2023EF003853), not undocumented updates. Full grids/manuscript outputs are unnecessary.

Derived reference CSV includes `LocID,year,reference_population_thousands,reference_allcause_mortality_rate` plus crosswalk metadata. Inspect builder/source schemas for raw age-group columns. Source data licence is separate from derivation code.

## RFF acquisition and remaining gaps

Installed MimiRFFSPs DataDeps registration references [rffsps_v5.7z](https://zenodo.org/records/6016583), SHA256 `a39b51d7552d198123b1863ea5a131533715a7a7c9ff6fad4b493594ece49497`. Follow that package's expected `rffsps_v5` DataDeps layout; do not reuse the old computer's depot path. New designs may require additional trajectories; obtain the dataset required by your selected IDs. Complete availability/extraction/rights on a new computer remain untested.

Wrapper hashes record core GIVE data, code, environment, scenario/design and minimum labour/MOMM inputs. Full RFF trajectory provenance requires a separate dataset manifest/package verification. This is explicitly incomplete, not certified offline reproducibility.

Private study inputs and outputs are not distributed. New scenarios need a finished methane intervention and model datasets. Comply with applicable dataset terms when obtaining or redistributing inputs; add a manifest with version/date/licence/transforms/units/hashes to scientific result bundles.
