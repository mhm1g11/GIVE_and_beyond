module ScenarioConfig
using TOML, SHA, Dates
export verify_stage_provenance, load_config, validate_inputs, config_from_args, record_provenance, read_numeric_csv

"""Portable, narrow CSV: unquoted numeric/identifier cells; blank records rejected."""
function read_numeric_csv(path)
    lines = readlines(path)
    isempty(lines) && error("Empty CSV: $path")
    header = strip.(split(first(lines), ','))
    length(unique(header)) == length(header) || error("Duplicate columns: $path")
    rows = [strip.(split(line, ','; keepempty=true)) for line in lines[2:end]]
    all(length(row) == length(header) for row in rows) || error("Malformed CSV: $path")
    return header, rows
end
function load_config(path)
    path = abspath(path); c = TOML.parsefile(path); base = dirname(path)
    get(c,"schema_version",0) == 1 || error("schema_version must be 1")
    resolve(p) = isabspath(p) ? normpath(p) : normpath(joinpath(base,p))
    run = c["run"]; inputs = c["inputs"]
    n = get(run,"trials",2); n isa Integer && n >= 2 || error("trials must be an integer >=2")
    y = get(run,"valuation_year",2025)
    y isa Integer && 2020 <= y <= 2100 || error("valuation_year must be in 2020:2100")
    scenarios = [(name=String(s["name"]),path=resolve(s["path"])) for s in c["scenarios"]]
    !isempty(scenarios) || error("At least one scenario is required")
    names = getproperty.(scenarios,:name)
    all(occursin(r"^[A-Za-z][A-Za-z0-9_-]*$",s) for s in names) || error("Unsafe scenario name")
    length(unique(names)) == length(names) || error("Duplicate scenario names")
    return (; path, trials=Int(n), valuation_year=Int(y), seed=Int(get(run,"seed",20260908)),
        output_dir=resolve(run["output_dir"]), scenarios,
        trial_design=resolve(inputs["trial_design"]), labor_design=resolve(inputs["labor_design"]),
        labor_root=resolve(inputs["labor_root"]), momm_root=resolve(inputs["momm_root"]),
        momm_socio=resolve(inputs["momm_socio"]), raw=c)
end
function config_from_args(args=ARGS)
    idx=findall(==("--config"), args)
    length(idx)==1 && only(idx)<length(args) || error("Use --config path/to/run.toml")
    return load_config(args[only(idx)+1])
end
function validate_inputs(c; external=false, ozone=true)
    for s in c.scenarios
        h, rows=read_numeric_csv(s.path)
        h == ["year","avoided_ch4_mt"] || error("Scenario columns must be year,avoided_ch4_mt: $(s.path)")
        years=parse.(Int,getindex.(rows,1)); values=parse.(Float64,getindex.(rows,2))
        length(unique(years))==length(years) || error("Duplicate scenario years")
        all(isfinite,values) && all(>=(0),values) || error("Avoided methane must be finite, nonnegative Mt CH4/year")
        all(1750 .<= years .<= 2300) || error("Scenario years outside 1750:2300")
        isempty(setdiff(c.valuation_year:2300,years)) || error("Supply every year through 2300; no implicit extension")
    end
    h,rows=read_numeric_csv(c.trial_design)
    h == ["trialnum","rffsp_id","fair_parameter_set_id"] || error("Invalid trial design columns")
    ints=[parse.(Int,row) for row in rows]
    length(ints)==c.trials || error("Trial count differs from configuration")
    getindex.(ints,1)==collect(1:c.trials) || error("Trials must be ordered consecutive 1:N")
    all(1<=row[2]<=10000 && 1<=row[3]<=2237 for row in ints) || error("Invalid RFF/FaIR IDs")
    lh,lr=read_numeric_csv(c.labor_design)
    lh == ["trialnum","rffsp_id","fair_parameter_set_id","labor_model_id","labor_model"] || error("Invalid labour design columns")
    length(lr)==c.trials || error("Labour design length mismatch")
    all(parse.(Int,row[1:3])==ints[i] && 2<=parse(Int,row[4])<=16 for (i,row) in enumerate(lr)) || error("Misaligned or invalid labour IDs")
    if external
        required = [joinpath(c.labor_root,"dimension_gcm.csv"),joinpath(c.labor_root,"region_crosswalk.csv"),
            joinpath(c.labor_root,"202505_SectorShare_v2.csv"),joinpath(c.labor_root,"ypc2017","rffsp_ypc2017_selected.csv"),
            joinpath(c.labor_root,"gtap_output","20260428_Plants_People_results_v4_ISO_Revision.csv"),
            joinpath(c.labor_root,"gtap_output","20260428_Plants_People_results_v4_Lancet_Revision.csv"),
            joinpath(c.momm_root,"input","BenMAP","Country Results Interpolated 2020-2100 by Model.csv"),
            joinpath(c.momm_root,"input","Final Country Grid Col_Row Index.csv"),c.momm_socio]
        !ozone && (required=required[1:6])
        missing=filter(!isfile,required)
        isempty(missing) || error("External files missing:\n"*join(missing,"\n"))
        _,g=read_numeric_csv(first(required)); labels=only.(g)
        length(labels)==16 && labels[1]=="model_ensemble" || error("Invalid labour dimension")
        all(labels[parse(Int,row[4])]==row[5] for row in lr) || error("Labour label/ID mismatch")
    end
    return true
end

function verify_stage_provenance(c,mode)
    records = [joinpath(c.output_dir,"provenance",stage*"_"*mode,"input_code_hashes.toml") for stage in ("climate","ozone")]
    all(isfile,records) || error("Missing climate/ozone input provenance; do not combine undocumented runs")
    tables=[TOML.parsefile(p)["sha256"] for p in records]
    shared=intersect(Set(keys(tables[1])),Set(keys(tables[2])))
    for p in shared
        tables[1][p]==tables[2][p] || error("Stage input/code mismatch: $p")
        isfile(p) && open(sha256,p) |> bytes2hex == tables[1][p] || error("Input/code changed since stage run: $p")
    end
    return true
end
function record_provenance(c,stage,mode)
    # Hash scientific inputs and code, never credentials, depot configs or Git config.
    out=joinpath(c.output_dir,"provenance",stage*"_"*mode)
    ispath(out) && error("Provenance already exists: $out")
    mkpath(out)
    paths=[c.path,c.trial_design,c.labor_design,getproperty.(c.scenarios,:path)...]
    root=normpath(joinpath(@__DIR__,".."))
    for sub in ("src","analysis","scripts","data")
        for (dir,_,files) in walkdir(joinpath(root,sub)), f in files
            (sub=="data" || endswith(f,".jl")) && push!(paths,joinpath(dir,f))
        end
    end
    append!(paths,[joinpath(root,"Project.toml"),joinpath(root,"Manifest.toml")])
    for sub in (c.labor_root,c.momm_root)
        # Minimum used files only; do not recurse large external data trees.
        rels = sub==c.labor_root ? ["dimension_gcm.csv","region_crosswalk.csv","202505_SectorShare_v2.csv","ypc2017/rffsp_ypc2017_selected.csv","gtap_output/20260428_Plants_People_results_v4_ISO_Revision.csv","gtap_output/20260428_Plants_People_results_v4_Lancet_Revision.csv"] : ["input/BenMAP/Country Results Interpolated 2020-2100 by Model.csv","input/Final Country Grid Col_Row Index.csv"]
        append!(paths,[joinpath(sub,r) for r in rels])
    end
    push!(paths,c.momm_socio)
    hashes=Dict(p=>open(sha256,p) |> bytes2hex for p in unique(paths) if isfile(p))
    open(joinpath(out,"input_code_hashes.toml"),"w") do io
        TOML.print(io,Dict("recorded_at"=>string(now()),"julia_version"=>string(VERSION),"stage"=>stage,"mode"=>mode,"sha256"=>hashes))
    end
    cp(c.path,joinpath(out,"run.toml"))
    for (label,p) in [("mc_trial_design.csv",c.trial_design),("labor_trial_design.csv",c.labor_design)]
        cp(p,joinpath(out,label))
    end
    return out
end
end
