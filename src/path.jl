using EasyMonad
# using Printf

struct Path 
    p::Maybe{String}
end

probe_path(p::Path)::Maybe{String} = begin 
    (isfile(p.p) || isdir(p.p)) && return p.p 
    return nothing
end

#TODO: better support for Maybe here, maybe
# pjoin(ps::Vector{Path})::Path = joinpath(map(x-> x >> x.p, ps)) |> Path

# pjoin(p1::Path, p2::Path)::Path = p1.p >> (p1 -> (p2.p >> (p2 -> Path(joinpath(p1, p2)))))
pjoin(p1::Path, p2::Path)::Path = begin 
    p1.p isa Nothing && return p2 
    p2.p isa Nothing && return p1 
    return Path(joinpath(p1.p, p2.p))
end
pjoin(ps::Vector{Path})::Path = reduce(pjoin, ps)

pcopy(from::Path, to::Path) = begin 
    @assert isfile(from.p) || isdir(from.p)
    if !(isfile(to.p)) && !(isdir(to.p))
        cp(from.p, to.p)
    end
end
pcd_run(p::Path, command::Base.AbstractCmd) = begin 
    current_dir = pwd()
    @assert isdir(p.p)
    cd(p.p)

    try
        run(command)
    catch e
        println(e)
    end

    cd(current_dir)
end

run_mkdir(p::Path) = begin 
    @assert !(isfile(p.p))
    if !(isdir(p.p)) 
        mkdir(p.p)
    end
end