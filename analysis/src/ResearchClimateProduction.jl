module ResearchClimateProduction

using Mimi, MimiGIVE, DataFrames, FileIO, CSVFiles, Random, Statistics

const SECTORS = (:cromar_mortality, :agriculture, :energy, :slr, :labor, :total)
const MC_SEED = 20260908

const EU27 = Set([
    "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN",
    "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX",
    "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"
])

"""Construct the opt-in hybrid; GIVE agriculture and its defaults are untouched."""
function climate_model(; include_labor=true, response=:ISO)
    include_labor || return MimiGIVE.get_model()
    response in (:ISO, :Lancet) || error("Expected ISO or Lancet")
    return MimiGIVE.get_model(include_labor=true, labor_response=response)
end

"""Existing SCC global annual streams include CIAM without legacy country streaming."""
function climate_options(design; last_year, discount_rates, gas, pulse_size)
    nrow(design) >= 2 ||
        error("The existing Mimi SampleStore MC path needs >=2 draws; use the deterministic smoke test for one trial")

    return (
        n=nrow(design),
        last_year=last_year,
        discount_rates=discount_rates,
        gas=gas,
        pulse_size=pulse_size,

        fair_parameter_set=:deterministic,
        fair_parameter_set_ids=Int.(design.fair_parameter_set_id),

        rffsp_sampling=:deterministic,
        rffsp_sampling_ids=Int.(design.rffsp_id),

        labor_model_ids=Int.(design.labor_model_id),

        compute_sectoral_values=true,
        compute_disaggregated_values=false,

        save_md=true,
        save_cpc=true,

        # Country outputs for regional labour and physical temperature mortality.
        save_list=[
            (:Labor, :laborcost),
            (:CromarMortality, :excess_deaths)
        ]
    )
end

"""Pure downstream conversion. Annual values stay undiscounted, USD2005/t gas.
Each formulation uses its own labour-adjusted baseline consumption for discounting.
"""
function climate_tables(
    result,
    design;
    response,
    pulse_year,
    last_year,
    discount_rates,
    gas
)
    years = collect(MimiGIVE._damages_years)

    cpc =
        result[:cpc][
            (region=:globe, sector=:total)
        ]

    size(cpc) == (nrow(design), length(years)) ||
        error("Consumption dimensions differ")

    streams =
        Dict(
            s =>
                result[:mds][
                    (region=:globe, sector=s)
                ]
            for s in SECTORS
        )

    all(size(v) == size(cpc) for v in values(streams)) ||
        error("Damage dimensions differ")

    isapprox(
        streams[:total],
        sum(
            streams[s]
            for s in SECTORS
            if s != :total
        );
        rtol=1e-8,
        atol=1e-5
    ) ||
        error("Annual sector sum differs from total (including CIAM)")

    annual = DataFrame()
    discounted = DataFrame()

    pulse_idx =
        findfirst(
            ==(pulse_year),
            years
        )

    isnothing(pulse_idx) &&
        error("Pulse year outside damage years")

    for (i, row) in enumerate(eachrow(design))

        identity = (
            trialnum=Int(row.trialnum),
            rffsp_id=Int(row.rffsp_id),
            fair_parameter_set_id=Int(row.fair_parameter_set_id),
            labor_model_id=Int(row.labor_model_id),
            labor_response=String(response),
            pulse_year=pulse_year,
            geography="globe"
        )

        for (j, year) in enumerate(years)

            year <= last_year ||
                continue

            for s in SECTORS

                push!(
                    annual,
                    merge(
                        identity,
                        (
                            impact_year=year,
                            sector=String(s),
                            marginal_damage=streams[s][i, j],
                            baseline_net_cpc=cpc[i, j],
                            unit="USD2005_per_t_$(gas)"
                        )
                    )
                )
            end
        end

        for dr in discount_rates

            idx =
                findall(
                    y ->
                        pulse_year <= y <= last_year,
                    years
                )

            df =
                (cpc[i, pulse_idx] ./ cpc[i, idx]).^dr.eta ./
                (1 + dr.prtp).^(years[idx] .- pulse_year)

            for s in SECTORS

                pv =
                    sum(
                        streams[s][i, idx] .* df
                    )

                key = (
                    region=:globe,
                    sector=s,
                    dr_label=dr.label,
                    prtp=dr.prtp,
                    eta=dr.eta,
                    ew=dr.ew,
                    ew_norm_region=dr.ew_norm_region
                )

                isapprox(
                    pv,
                    result[:scc][key].sccs[i];
                    rtol=1e-8,
                    atol=1e-5
                ) ||
                    error(
                        "Downstream PV differs from GIVE for $s"
                    )

                push!(
                    discounted,
                    merge(
                        identity,
                        (
                            sector=String(s),
                            value=pv,
                            dr_label=dr.label,
                            prtp=dr.prtp,
                            eta=dr.eta,
                            last_year=last_year,
                            unit="USD2005_per_t_$(gas)"
                        )
                    )
                )
            end
        end
    end

    return (
        annual=annual,
        discounted=discounted
    )
end

"""Build EU27 and Germany labour SCCs from country-level labour damages.

The country-level global sum is checked against GIVE's native global labour SCC.
Only EU27 and DEU are returned, because the native global labour result already
exists in climate_tables().
"""
function regional_labor_discounted(
    result,
    design,
    run_dir;
    response,
    pulse_year,
    last_year,
    discount_rates,
    gas,
    pulse_size
)

    gas == :CH4 ||
        error(
            "Regional labour conversion is currently defined for CH4 production runs."
        )

    base_path =
        joinpath(
            run_dir,
            "results",
            "model_1",
            "Labor_laborcost.csv"
        )

    pulse_path =
        joinpath(
            run_dir,
            "results",
            "model_2",
            "Labor_laborcost.csv"
        )

    isfile(base_path) ||
        error(
            "Missing baseline labour output: $base_path"
        )

    isfile(pulse_path) ||
        error(
            "Missing pulse labour output: $pulse_path"
        )

    base =
        DataFrame(
            load(base_path)
        )

    pulse =
        DataFrame(
            load(pulse_path)
        )

    rename!(
        base,
        :laborcost =>
            :laborcost_base
    )

    rename!(
        pulse,
        :laborcost =>
            :laborcost_pulse
    )

    labor =
        innerjoin(
            base,
            pulse,
            on=[
                :time,
                :country,
                :trialnum
            ]
        )

    labor.time =
        Int.(labor.time)

    labor.trialnum =
        Int.(labor.trialnum)

    labor.country =
        String.(labor.country)

    labor =
        filter(
            row ->
                pulse_year <= row.time <= last_year &&
                !ismissing(row.laborcost_base) &&
                !ismissing(row.laborcost_pulse),
            labor
        )

    countries =
        Set(
            labor.country
        )

    missing_eu =
        setdiff(
            EU27,
            countries
        )

    isempty(missing_eu) ||
        error(
            "EU27 labour aggregation is missing countries: " *
            string(
                sort(
                    collect(
                        missing_eu
                    )
                )
            )
        )

    "DEU" in countries ||
        error(
            "Germany is missing from labour country output."
        )

    expected_trials =
        Int.(design.trialnum)

    actual_trials =
        sort(
            unique(
                labor.trialnum
            )
        )

    actual_trials == expected_trials ||
        error(
            "Country-level labour outputs do not match the aligned trial design."
        )

    # laborcost is billion USD2005/year.
    # CH4 pulse_size is in Mt CH4.
    #
    # billion USD / Mt CH4 = 1,000 USD/t CH4.
    conversion =
        1e9 /
        (
            pulse_size *
            1e6
        )

    labor.marginal_damage =
        (
            Float64.(labor.laborcost_pulse) .-
            Float64.(labor.laborcost_base)
        ) .* conversion

    years =
        collect(
            MimiGIVE._damages_years
        )

    pulse_idx =
        findfirst(
            ==(pulse_year),
            years
        )

    isnothing(pulse_idx) &&
        error(
            "Pulse year outside damage years."
        )

    idx =
        findall(
            y ->
                pulse_year <= y <= last_year,
            years
        )

    cpc =
        result[:cpc][
            (region=:globe, sector=:total)
        ]

    global_labor_stream =
        result[:mds][
            (region=:globe, sector=:labor)
        ]

    output =
        DataFrame()

    for (i, design_row) in enumerate(eachrow(design))

        trialnum =
            Int(
                design_row.trialnum
            )

        trial =
            labor[
                labor.trialnum .== trialnum,
                :
            ]

        for geography in (
            "globe",
            "EU27",
            "DEU"
        )

            geo =
                if geography == "globe"

                    trial

                elseif geography == "EU27"

                    trial[
                        in.(trial.country, Ref(EU27)),
                        :
                    ]

                else

                    trial[
                        trial.country .== "DEU",
                        :
                    ]
                end

            annual =
                combine(
                    groupby(
                        geo,
                        :time
                    ),
                    :marginal_damage =>
                        sum =>
                        :marginal_damage
                )

            md_lookup =
                Dict(
                    Int(row.time) =>
                        Float64(
                            row.marginal_damage
                        )
                    for row in eachrow(annual)
                )

            missing_years =
                [
                    year
                    for year in years[idx]
                    if !haskey(
                        md_lookup,
                        year
                    )
                ]

            isempty(missing_years) ||
                error(
                    "Missing $geography labour years for trial $trialnum: " *
                    string(missing_years)
                )

            md =
                [
                    md_lookup[year]
                    for year in years[idx]
                ]

            if geography == "globe"

                isapprox(
                    md,
                    global_labor_stream[i, idx];
                    rtol=1e-8,
                    atol=1e-5
                ) ||
                    error(
                        "Country-summed annual labour damages differ from GIVE global labour stream for trial $trialnum."
                    )
            end

            for dr in discount_rates

                df =
                    (
                        cpc[i, pulse_idx] ./
                        cpc[i, idx]
                    ).^dr.eta ./
                    (
                        1 + dr.prtp
                    ).^(
                        years[idx] .-
                        pulse_year
                    )

                pv =
                    sum(
                        md .* df
                    )

                if geography == "globe"

                    key = (
                        region=:globe,
                        sector=:labor,
                        dr_label=dr.label,
                        prtp=dr.prtp,
                        eta=dr.eta,
                        ew=dr.ew,
                        ew_norm_region=dr.ew_norm_region
                    )

                    isapprox(
                        pv,
                        result[:scc][key].sccs[i];
                        rtol=1e-8,
                        atol=1e-5
                    ) ||
                        error(
                            "Country-summed discounted labour damages differ from GIVE global labour SCC for trial $trialnum."
                        )

                    # Global labour is already in climate_tables().
                    continue
                end

                push!(
                    output,
                    (
                        trialnum=trialnum,
                        rffsp_id=Int(
                            design_row.rffsp_id
                        ),
                        fair_parameter_set_id=Int(
                            design_row.fair_parameter_set_id
                        ),
                        labor_model_id=Int(
                            design_row.labor_model_id
                        ),
                        labor_response=String(
                            response
                        ),
                        pulse_year=pulse_year,
                        geography=geography,
                        sector="labor",
                        value=pv,
                        dr_label=dr.label,
                        prtp=dr.prtp,
                        eta=dr.eta,
                        last_year=last_year,
                        unit="USD2005_per_t_$(gas)"
                    )
                )
            end
        end
    end

    return output
end

"""Extract undiscounted physical deaths; positive values mean pulse-induced deaths.
Mimi joins the save_list component/variable with '_' under results/model_1/2.
"""
function physical_temperature_mortality(design, run_dir; response, pulse_year,
        last_year, gas, pulse_size, expected_countries)
    gas == :CH4 || error("Physical mortality normalization requires CH4")
    isfinite(pulse_size) && pulse_size > 0 || error("Expected a positive Mt CH4 pulse")
    pulse_year <= last_year || error("Invalid mortality impact period")
    trials = sort(Int.(design.trialnum))
    length(unique(trials)) == length(trials) || error("Duplicate design trials")
    countries = Set(String.(expected_countries))
    issubset(EU27, countries) && "DEU" in countries || error("Missing EU27/DEU countries")
    years = collect(pulse_year:last_year)
    keys = [:trialnum, :time, :country]
    function read_mortality(model_index)
        path = joinpath(run_dir, "results", "model_$(model_index)",
            "CromarMortality_excess_deaths.csv")
        isfile(path) || error("Missing physical mortality output: $path")
        df = DataFrame(load(path))
        all(c -> c in propertynames(df), [keys; :excess_deaths]) || error("Invalid mortality columns: $path")
        any(ismissing, df.time) && error("Missing mortality year: $path")
        df.time = Int.(df.time)
        df = df[(pulse_year .<= df.time) .& (df.time .<= last_year), :]
        any(c -> any(ismissing, df[!,c]), [keys; :excess_deaths]) &&
            error("Missing annual mortality values: $path")
        df.trialnum = Int.(df.trialnum)
        df.country = String.(df.country)
        df.excess_deaths = Float64.(df.excess_deaths)
        all(isfinite, df.excess_deaths) || error("Nonfinite mortality: $path")
        sort(unique(df.trialnum)) == trials || error("Mortality trial coverage differs: $path")
        Set(df.country) == countries || error("Mortality country coverage differs: $path")
        sort(unique(df.time)) == years || error("Mortality year coverage differs: $path")
        # Unique keys plus exact Cartesian-product size require every country/year/trial.
        nrow(unique(select(df, keys))) == nrow(df) || error("Duplicate mortality keys: $path")
        nrow(df) == length(trials)*length(years)*length(countries) ||
            error("Incomplete annual mortality grid: $path")
        return sort(df, keys)
    end
    base, pulse = read_mortality(1), read_mortality(2)
    isequal(select(base, keys), select(pulse, keys)) || error("Unmatched mortality model keys")
    country = select(base, keys)
    country.baseline_deaths = base.excess_deaths
    country.pulse_deaths = pulse.excess_deaths
    country.deaths_per_mt_ch4 = (pulse.excess_deaths .- base.excess_deaths) ./ pulse_size
    all(isfinite, country.deaths_per_mt_ch4) || error("Nonfinite pulse mortality")
    annual = DataFrame(pulse_year=Int[], response=String[], trial=Int[],
        year=Int[], geography=String[], deaths_per_mt_ch4=Float64[])
    for g in groupby(country, [:trialnum, :time])
        trial, year = g.trialnum[1], g.time[1]
        global_deaths = sum(g.deaths_per_mt_ch4)
        # Independent sum-before-difference check, allowing floating-point cancellation.
        b, p = g.baseline_deaths, g.pulse_deaths
        roundoff = 32*eps(Float64)*(sum(abs, b)+sum(abs, p))/pulse_size
        isapprox(global_deaths, (sum(p)-sum(b))/pulse_size;
            rtol=1e-10, atol=max(1e-10, roundoff)) ||
            error("Global mortality differs from country sum for trial $trial / $year")
        for geography in ("globe", "EU27", "DEU")
            deaths = geography == "globe" ? global_deaths :
                sum(g.deaths_per_mt_ch4[geography == "EU27" ?
                    in.(g.country, Ref(EU27)) : g.country .== "DEU"])
            push!(annual, (pulse_year, String(response), trial, year, geography, deaths))
        end
    end
    sort!(annual, [:pulse_year, :response, :trial, :year, :geography])
    cumulative = combine(groupby(annual, [:pulse_year, :response, :trial, :geography]),
        :deaths_per_mt_ch4 => sum => :deaths_per_mt_ch4)
    return (; annual, cumulative)
end

"""Require rowwise ISO/Lancet equality, then retain ISO without averaging."""
function central_temperature_mortality(table; annual)
    Set(table.response) == Set(["ISO", "Lancet"]) || error("Both mortality responses required")
    keys = annual ? [:pulse_year, :trial, :year, :geography] :
        [:pulse_year, :trial, :geography]
    iso = sort(table[table.response .== "ISO", :], keys)
    lancet = sort(table[table.response .== "Lancet", :], keys)
    nrow(unique(select(iso, keys))) == nrow(iso) || error("Duplicate ISO mortality rows")
    nrow(unique(select(lancet, keys))) == nrow(lancet) || error("Duplicate Lancet mortality rows")
    isequal(select(iso, keys), select(lancet, keys)) || error("Unmatched ISO/Lancet mortality coverage")
    all(isfinite, iso.deaths_per_mt_ch4) && all(isfinite, lancet.deaths_per_mt_ch4) ||
        error("Nonfinite ISO/Lancet mortality")
    all(isapprox.(iso.deaths_per_mt_ch4, lancet.deaths_per_mt_ch4;
        rtol=1e-10, atol=1e-10)) || error("ISO/Lancet physical mortality differs; refusing to average")
    return select(iso, [keys; :deaths_per_mt_ch4])
end

"""Average final discounted formulation means only; no combined trial distribution."""
function central_labor(discounted)

    lab =
        discounted[
            discounted.sector .== "labor",
            :
        ]

    output =
        DataFrame()

    for g in groupby(
        lab,
        [
            :pulse_year,
            :geography,
            :dr_label,
            :prtp,
            :eta,
            :last_year,
            :unit
        ]
    )

        Set(g.labor_response) ==
            Set([
                "ISO",
                "Lancet"
            ]) ||
            error(
                "Both formulations are required for central labour"
            )

        iso =
            g[
                g.labor_response .== "ISO",
                :
            ]

        lancet =
            g[
                g.labor_response .== "Lancet",
                :
            ]

        keys = [
            :trialnum,
            :rffsp_id,
            :fair_parameter_set_id,
            :labor_model_id
        ]

        isequal(
            sort(
                select(
                    iso,
                    keys
                ),
                :trialnum
            ),
            sort(
                select(
                    lancet,
                    keys
                ),
                :trialnum
            )
        ) ||
            error(
                "Unmatched formulation trials"
            )

        nrow(
            unique(
                select(
                    iso,
                    keys
                )
            )
        ) == nrow(iso) ||
            error(
                "Duplicate trial"
            )

        push!(
            output,
            (
                pulse_year=g.pulse_year[1],
                geography=g.geography[1],
                sector="labor",
                statistic="mean_of_ISO_Lancet_discounted_means",
                value=(
                    mean(iso.value) +
                    mean(lancet.value)
                ) / 2,
                dr_label=g.dr_label[1],
                prtp=g.prtp[1],
                eta=g.eta[1],
                last_year=g.last_year[1],
                unit=g.unit[1],
                n_trials_per_response=nrow(iso)
            )
        )
    end

    return output
end

"""Production entry point.

Global climate-sector streams are taken directly from GIVE.
Labour is additionally aggregated from country outputs for EU27 and Germany.
"""
function build_labor_library(
    ;
    design,
    seed=MC_SEED,
    output_dir,
    pulse_years,
    responses,
    last_year,
    discount_rates,
    gas,
    pulse_size
)

    Set(responses) ==
        Set((
            :ISO,
            :Lancet
        )) &&
        length(responses) == 2 ||
        error(
            "Production requires separate ISO and Lancet calculations"
        )

    all(
        isnothing(dr.ew)
        for dr in discount_rates
    ) ||
        error(
            "Only global Ramsey valuation is supported"
        )

    options =
        climate_options(
            design;
            last_year=last_year,
            discount_rates=discount_rates,
            gas=gas,
            pulse_size=pulse_size
        )

    mkpath(
        output_dir
    )

    discounted =
        DataFrame()

    mortality_annual = DataFrame()
    mortality_cumulative = DataFrame()

    references =
        Dict{
            Symbol,
            Any
        }()

    for pulse_year in pulse_years,
        response in responses

        println(
            "Climate/labour production: ",
            pulse_year,
            " / ",
            response
        )

        model =
            climate_model(
                ;
                response=response
            )

        # Preserve all original GIVE stochastic draws across
        # pulse years and labour formulations.
        Random.seed!(seed)

        run_dir =
            joinpath(
                output_dir,
                "runs",
                "$(response)_$(pulse_year)"
            )

        result =
            MimiGIVE.compute_scc(
                model;
                year=pulse_year,
                options...,
                output_dir=run_dir
            )

        cpc =
            result[:cpc][
                (
                    region=:globe,
                    sector=:total
                )
            ]

        if haskey(
            references,
            response
        )

            isapprox(
                cpc,
                references[response];
                rtol=0,
                atol=1e-10
            ) ||
                error(
                    "Consumption trial alignment changed"
                )

        else

            references[response] =
                copy(
                    cpc
                )
        end

        tables =
            climate_tables(
                result,
                design;
                response=response,
                pulse_year=pulse_year,
                last_year=last_year,
                discount_rates=discount_rates,
                gas=gas
            )

        save(
            joinpath(
                output_dir,
                "annual_$(response)_$(pulse_year).csv"
            ),
            tables.annual
        )

        append!(
            discounted,
            tables.discounted;
            cols=:union
        )

        regional =
            regional_labor_discounted(
                result,
                design,
                run_dir;
                response=response,
                pulse_year=pulse_year,
                last_year=last_year,
                discount_rates=discount_rates,
                gas=gas,
                pulse_size=pulse_size
            )

        append!(
            discounted,
            regional;
            cols=:union
        )

        physical = physical_temperature_mortality(design, run_dir;
            response, pulse_year, last_year, gas, pulse_size,
            expected_countries=String.(Mimi.dim_keys(model, :country)))
        append!(mortality_annual, physical.annual; cols=:union)
        append!(mortality_cumulative, physical.cumulative; cols=:union)

        println(
            "  regional labour QA passed for Global / EU27 / DEU"
        )
    end

    save(
        joinpath(
            output_dir,
            "discounted_sector_trials.csv"
        ),
        discounted
    )

    save(
        joinpath(
            output_dir,
            "central_labor_mean.csv"
        ),
        central_labor(
            discounted
        )
    )

    # Validate both annual and cumulative equality before writing either central table.
    central_annual = central_temperature_mortality(mortality_annual; annual=true)
    central_cumulative = central_temperature_mortality(mortality_cumulative; annual=false)
    save(joinpath(output_dir, "temperature_mortality_annual_trials.csv"), central_annual)
    save(joinpath(output_dir, "temperature_mortality_cumulative_trials.csv"), central_cumulative)

    return nothing
end

end
