using Test
root=normpath(joinpath(@__DIR__,".."))
function valid_ast(x)
    x isa Expr || return true
    x.head in (:error,:incomplete) && return false
    return all(valid_ast,x.args)
end
@testset "Julia syntax (no includes/model execution)" begin
    for sub in ("src","analysis","scripts","test"), (dir,_,files) in walkdir(joinpath(root,sub)), f in files
        endswith(f,".jl") || continue
        path=joinpath(dir,f)
        @test valid_ast(Meta.parseall(read(path,String);filename=path))
    end
end
